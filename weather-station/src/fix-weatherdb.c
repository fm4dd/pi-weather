/*
 * fix-weatherdb.c
 *
 * Finds and fixes bad samples in a weather-station RRD (created with
 * rrdtool) over a requested lookback period. "Bad" means either:
 *   - a literal NaN (sensor read failure), or
 *   - an implausible value: a sudden jump away from the recent rolling
 *     baseline for that data source, indicating a sensor fault that
 *     still returned a (wrong) number instead of NaN.
 *
 * Method:
 *   1. rrd_dump() the RRD to a temporary XML file (the public, stable
 *      librrd argc/argv API - the same one the rrdtool CLI itself uses).
 *   2. Scan RRA[0] (the raw, native-step archive) first. This is the
 *      only place "sudden jump" is a meaningful test. Each raw sample is
 *      compared to the mean of the last N_BASELINE *good* samples for
 *      that DS; NaN or an out-of-threshold jump marks it bad. Bad runs
 *      are linearly interpolated between the last good value before the
 *      run and the first good value after it, producing a corrected raw
 *      timeline held in memory.
 *   3. For every other (consolidated) archive, each row is recomputed
 *      directly from the corrected raw timeline (proper AVERAGE / MIN /
 *      MAX over that row's exact time span, honoring the archive's xff),
 *      rather than trusting whatever value is currently stored there -
 *      this is what fixes silent corruption in aggregates that isn't
 *      itself NaN (which a same-archive NaN-only scan would miss).
 *   4. If a consolidated row's time span has already rolled out of the
 *      raw archive's retention window, recomputation isn't possible; as
 *      an approximation, that row falls back to being linearly
 *      interpolated using neighbouring valid rows within its own archive
 *      (this only catches literal NaN, not silent corruption, since we
 *      no longer have the source data to detect anything more).
 *   5. If -w is given, patches are applied to the dumped XML and
 *      rrd_restore()'d into a new file. The original is backed up to
 *      <file>.bak first, then atomically replaced.
 *
 * 'dayt' (a day/night 0/1 flag) is never analyzed or touched.
 *
 * Build: gcc -O2 -Wall fix-weatherdb.c -o fix-weatherdb -lrrd
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <time.h>
#include <math.h>
#include <errno.h>
#include <libgen.h>
#include <sys/stat.h>
#include <limits.h>
#include <rrd.h>

#define MAX_DS      4
#define MAX_RRA     16

/* --- implausible-value thresholds: max change vs. the rolling baseline
 *     of the last N_BASELINE good raw (native-step) samples. Tune these
 *     to match real sensor behaviour; they only apply to the raw archive. */
#define THRESH_TEMP   15.0   /* degrees C per raw step   */
#define THRESH_HUMI   30.0   /* percentage points        */
#define THRESH_BMPR 1000.0   /* Pa (10 hPa) per raw step */

#define N_BASELINE            5   /* how many past good samples to average   */
#define MIN_BASELINE_FOR_CHECK 3  /* need at least this many before judging  */

static const char *ds_name[MAX_DS]     = { "temp", "humi", "bmpr", "dayt" };
static const int   ds_fixable[MAX_DS]  = { 1, 1, 1, 0 };
static const double bad_threshold[MAX_DS] = { THRESH_TEMP, THRESH_HUMI, THRESH_BMPR, 0 };

enum { REASON_GOOD = 0, REASON_NAN = 1, REASON_OUTLIER = 2 };

int  opt_debug   = 0;
int  opt_write   = 0;
time_t win_start = 0;
time_t win_end   = 0;

/* ---- a pending text patch: replace old_len bytes at file offset 'off'
 *      with a freshly formatted number ---- */
typedef struct {
    long  off;
    int   old_len;
    char  text[32];
} Patch;

static Patch *patches = NULL;
static long   patch_count = 0;
static long   patch_cap   = 0;

/* points written per data-source per RRA index (only meaningful with -w) */
static long fixed_points[MAX_DS][MAX_RRA];

/* the corrected raw (RRA[0]) timeline, per DS - built while scanning RRA[0],
 * then used to recompute every consolidated archive's rows. */
typedef struct {
    time_t ts;
    double val;   /* corrected value; NaN if still-unresolved (open-ended) bad run */
    int    bad;   /* 1 if this raw sample was originally NaN or an outlier */
} RawPoint;

static RawPoint *raw_pts[MAX_DS];
static long      raw_len[MAX_DS];
static long      raw_cap[MAX_DS];

static long raw_push(int ds, time_t ts, double val, int bad) {
    if (raw_len[ds] >= raw_cap[ds]) {
        raw_cap[ds] = raw_cap[ds] ? raw_cap[ds] * 2 : 4096;
        raw_pts[ds] = realloc(raw_pts[ds], raw_cap[ds] * sizeof(RawPoint));
    }
    RawPoint *r = &raw_pts[ds][raw_len[ds]];
    r->ts = ts; r->val = val; r->bad = bad;
    return raw_len[ds]++;
}

/* one reported gap, always from RRA[0] (raw) analysis, or from the
 * old-style same-archive fallback used on out-of-retention rows */
typedef struct {
    int    rra;
    int    ds;
    time_t t_first_nan;
    time_t t_last_nan;
    double v_before;
    double v_after;
    time_t t_before;
    time_t t_after;
    int    bounded;
    long   n_points;
    long   n_nan;
    long   n_outlier;
    int    fixed;
} GapEvent;

static GapEvent *gaps = NULL;
static long gap_count = 0;
static long gap_cap = 0;

static void gap_add(GapEvent g) {
    if (gap_count >= gap_cap) {
        gap_cap = gap_cap ? gap_cap * 2 : 64;
        gaps = realloc(gaps, gap_cap * sizeof(GapEvent));
    }
    gaps[gap_count++] = g;
}

static void patch_add(long off, int old_len, double value) {
    if (patch_count >= patch_cap) {
        patch_cap = patch_cap ? patch_cap * 2 : 1024;
        patches = realloc(patches, patch_cap * sizeof(Patch));
    }
    Patch *p = &patches[patch_count++];
    p->off = off;
    p->old_len = old_len;
    snprintf(p->text, sizeof(p->text), "%.10e", value);
}

/* ---------------------------------------------------------------------
 * per (ds) streaming state while scanning one <database> section.
 * Used both for RRA[0]'s raw+outlier run detection, and (unchanged
 * semantics) as the same-archive fallback for higher RRAs whose rows can
 * no longer be recomputed from raw data.
 * --------------------------------------------------------------------- */
typedef struct {
    int     have_valid;
    double  last_valid_val;
    time_t  last_valid_ts;

    int     run_active;
    time_t  run_first_ts;
    time_t  run_last_ts;
    long    run_nan_count;
    long    run_outlier_count;

    long    buf_len, buf_cap;
    long   *buf_off;
    int    *buf_len_arr;   /* original token byte length at buf_off[i] */
    time_t *buf_ts;
    long   *buf_rawidx;    /* index into raw_pts[ds], only used for RRA[0] */

    /* rolling baseline of the last N_BASELINE good raw values (RRA[0] only) */
    double  ring[N_BASELINE];
    int     ring_count;
    int     ring_pos;
} DsState;

static DsState state[MAX_DS];
static int current_rra = -1;
static char current_cf[32];
static int  current_pdp_per_row = 1;
static long global_step = 60;
static int  in_database = 0;

static char rra_cf[MAX_RRA][32];
static int  rra_pdp_per_row[MAX_RRA];
static double rra_xff[MAX_RRA];

static void state_reset_all(void) {
    for (int i = 0; i < MAX_DS; i++) {
        state[i].have_valid = 0;
        state[i].run_active = 0;
        state[i].buf_len = 0;
        state[i].ring_count = 0;
        state[i].ring_pos = 0;
    }
}

static void buf_push_full(DsState *st, long off, int len, time_t ts, long rawidx) {
    if (st->buf_len >= st->buf_cap) {
        st->buf_cap = st->buf_cap ? st->buf_cap * 2 : 64;
        st->buf_off     = realloc(st->buf_off,     st->buf_cap * sizeof(long));
        st->buf_len_arr = realloc(st->buf_len_arr, st->buf_cap * sizeof(int));
        st->buf_ts      = realloc(st->buf_ts,      st->buf_cap * sizeof(time_t));
        st->buf_rawidx  = realloc(st->buf_rawidx,  st->buf_cap * sizeof(long));
    }
    st->buf_off[st->buf_len]     = off;
    st->buf_len_arr[st->buf_len] = len;
    st->buf_ts[st->buf_len]      = ts;
    st->buf_rawidx[st->buf_len]  = rawidx;
    st->buf_len++;
}

static double ring_avg(DsState *st) {
    double sum = 0;
    for (int i = 0; i < st->ring_count; i++) sum += st->ring[i];
    return sum / st->ring_count;
}

static void ring_push(DsState *st, double v) {
    st->ring[st->ring_pos] = v;
    st->ring_pos = (st->ring_pos + 1) % N_BASELINE;
    if (st->ring_count < N_BASELINE) st->ring_count++;
}

static int window_intersects(time_t a, time_t b) {
    return (a <= win_end && b >= win_start);
}

static const char *rra_label(int rra) {
    static char buf[64];
    const char *cf = (rra >= 0 && rra < MAX_RRA) ? rra_cf[rra] : "?";
    long pdp = (rra >= 0 && rra < MAX_RRA) ? rra_pdp_per_row[rra] : 1;
    snprintf(buf, sizeof(buf), "RRA[%d] (%s, step %lds)", rra,
             cf[0] ? cf : "?", pdp * global_step);
    return buf;
}

/* Resolve a just-closed bad run for ds. is_raw=1 means this is RRA[0]
 * (writes corrected values back into raw_pts[] for later recompute use);
 * is_raw=0 means this is the old same-archive fallback for a higher RRA. */
static void resolve_run(int rra, int ds, DsState *st,
                         int have_end, double v_end, time_t t_end, int is_raw) {
    if (st->buf_len == 0) return;

    GapEvent g;
    memset(&g, 0, sizeof(g));
    g.rra = rra;
    g.ds  = ds;
    g.t_first_nan = st->run_first_ts;
    g.t_last_nan  = st->run_last_ts;
    g.n_points    = st->buf_len;
    g.n_nan       = st->run_nan_count;
    g.n_outlier   = st->run_outlier_count;
    g.bounded     = st->have_valid && have_end;
    g.v_before    = st->last_valid_val;
    g.t_before    = st->last_valid_ts;
    g.v_after     = v_end;
    g.t_after     = t_end;
    g.fixed       = 0;

    if (!window_intersects(g.t_first_nan, g.t_last_nan)) {
        st->buf_len = 0;
        return; /* outside the requested -b window: ignore entirely */
    }

    if (g.bounded) {
        double span = (double)(g.t_after - g.t_before);
        for (long i = 0; i < st->buf_len; i++) {
            time_t ts = st->buf_ts[i];
            double frac = (span > 0) ? (double)(ts - g.t_before) / span : 0.0;
            double val = g.v_before + (g.v_after - g.v_before) * frac;
            if (is_raw) raw_pts[ds][st->buf_rawidx[i]].val = val;
            if (opt_write) {
                patch_add(st->buf_off[i], st->buf_len_arr[i], val);
                fixed_points[ds][rra]++;
            }
        }
        g.fixed = opt_write;
    }

    gap_add(g);
    st->buf_len = 0;
}

/* ---------------------------------------------------------------------
 * recompute a consolidated row directly from the corrected raw timeline.
 * Returns 1 if raw data fully covers this row's span (recompute is
 * authoritative), 0 if raw retention doesn't reach back far enough.
 * out_any_bad is set to 1 if the underlying raw span contained at least
 * one originally-bad sample (i.e. this row needed fixing at all).
 * --------------------------------------------------------------------- */
static int try_recompute_from_raw(int ds, int rra, time_t row_ts, int pdp_per_row,
                                   double *out_val, int *out_any_bad) {
    if (pdp_per_row <= 0 || raw_len[ds] == 0) return 0;

    long lo = 0, hi = raw_len[ds] - 1, idx_end = -1;
    while (lo <= hi) {
        long mid = (lo + hi) / 2;
        if (raw_pts[ds][mid].ts == row_ts) { idx_end = mid; break; }
        else if (raw_pts[ds][mid].ts < row_ts) lo = mid + 1;
        else hi = mid - 1;
    }
    if (idx_end < 0) return 0;

    long idx_start = idx_end - (pdp_per_row - 1);
    if (idx_start < 0) return 0;

    for (long i = idx_start + 1; i <= idx_end; i++) {
        if (raw_pts[ds][i].ts - raw_pts[ds][i - 1].ts != global_step) return 0;
    }

    int any_bad = 0, known = 0;
    double sum = 0, mn = 0, mx = 0;
    int have_mm = 0;
    for (long i = idx_start; i <= idx_end; i++) {
        RawPoint *r = &raw_pts[ds][i];
        if (r->bad) any_bad = 1;
        if (isnan(r->val)) continue;
        known++;
        sum += r->val;
        if (!have_mm) { mn = mx = r->val; have_mm = 1; }
        else { if (r->val < mn) mn = r->val; if (r->val > mx) mx = r->val; }
    }

    *out_any_bad = any_bad;
    if (!any_bad) return 1; /* coverage OK, nothing needed fixing */

    double xff = (rra >= 0 && rra < MAX_RRA) ? rra_xff[rra] : 0.5;
    double unknown_frac = (double)(pdp_per_row - known) / (double)pdp_per_row;

    double result;
    if (known == 0 || unknown_frac > xff) {
        result = NAN;
    } else {
        const char *cf = (rra >= 0 && rra < MAX_RRA) ? rra_cf[rra] : "";
        if (strcasecmp(cf, "AVERAGE") == 0) result = sum / known;
        else if (strcasecmp(cf, "MIN") == 0) result = mn;
        else if (strcasecmp(cf, "MAX") == 0) result = mx;
        else return 0; /* unrecognized CF: let the old fallback handle it */
    }
    *out_val = result;
    return 1;
}

/* handle one raw (RRA[0]) sample: NaN/outlier detection + run tracking */
static void handle_raw_row(int ds, time_t ts, double val, int is_nan, long off, int len) {
    DsState *st = &state[ds];
    int reason;
    if (is_nan) {
        reason = REASON_NAN;
    } else if (st->ring_count >= MIN_BASELINE_FOR_CHECK &&
               fabs(val - ring_avg(st)) > bad_threshold[ds]) {
        reason = REASON_OUTLIER;
    } else {
        reason = REASON_GOOD;
    }
    int bad = (reason != REASON_GOOD);
    long ridx = raw_push(ds, ts, bad ? NAN : val, bad);

    if (!bad) {
        if (st->run_active) {
            resolve_run(0, ds, st, 1, val, ts, 1);
            st->run_active = 0;
        }
        st->have_valid = 1;
        st->last_valid_val = val;
        st->last_valid_ts = ts;
        ring_push(st, val);
    } else {
        if (!st->run_active) {
            st->run_active = 1;
            st->run_first_ts = ts;
            st->buf_len = 0;
            st->run_nan_count = 0;
            st->run_outlier_count = 0;
        }
        st->run_last_ts = ts;
        buf_push_full(st, off, len, ts, ridx);
        if (reason == REASON_NAN) st->run_nan_count++; else st->run_outlier_count++;
    }
}

/* handle one row of a consolidated (non-raw) RRA */
static void handle_other_rra_row(int rra, int ds, time_t ts, double val, int is_nan,
                                  long off, int len, int pdp_per_row) {
    double recomputed = NAN;
    int any_bad = 0;
    if (try_recompute_from_raw(ds, rra, ts, pdp_per_row, &recomputed, &any_bad)) {
        /* recompute is authoritative for this row regardless of scope, but
         * only actually TOUCH it if its timestamp falls within the
         * requested -b window - otherwise this would silently patch data
         * far outside what the user asked to check. */
        if (any_bad && window_intersects(ts, ts)) {
            if (opt_write) {
                patch_add(off, len, recomputed);
                fixed_points[ds][rra]++;
            }
            if (opt_debug) {
                char tb[32]; struct tm tmv; localtime_r(&ts, &tmv);
                strftime(tb, sizeof(tb), "%Y-%m-%d %H:%M:%S", &tmv);
                printf("[%s] DS %-4s: row %s recomputed from raw (%s)\n",
                       rra_label(rra), ds_name[ds], tb, opt_write ? "written" : "would write");
            }
        }
        return; /* raw covered this row - authoritative, no need for old fallback */
    }

    /* raw retention doesn't reach this far back: fall back to the old
     * same-archive literal-NaN interpolation (approximation only) */
    DsState *st = &state[ds];
    if (!is_nan) {
        if (st->run_active) {
            resolve_run(rra, ds, st, 1, val, ts, 0);
            st->run_active = 0;
        }
        st->have_valid = 1;
        st->last_valid_val = val;
        st->last_valid_ts = ts;
    } else {
        if (!st->run_active) {
            st->run_active = 1;
            st->run_first_ts = ts;
            st->buf_len = 0;
        }
        st->run_last_ts = ts;
        buf_push_full(st, off, 3, ts, -1);
    }
}

/* ---------------------------------------------------------------------
 * XML line parsing
 * --------------------------------------------------------------------- */

static void extract_tag_int(const char *line, const char *tag, long *out) {
    char open_tag[32], close_tag[32];
    snprintf(open_tag, sizeof(open_tag), "<%s>", tag);
    snprintf(close_tag, sizeof(close_tag), "</%s>", tag);
    const char *s = strstr(line, open_tag);
    if (!s) return;
    s += strlen(open_tag);
    const char *e = strstr(s, close_tag);
    if (!e) return;
    char buf[64];
    size_t len = (size_t)(e - s);
    if (len >= sizeof(buf)) len = sizeof(buf) - 1;
    memcpy(buf, s, len);
    buf[len] = '\0';
    *out = strtol(buf, NULL, 10);
}

static void extract_tag_double(const char *line, const char *tag, double *out) {
    char open_tag[32], close_tag[32];
    snprintf(open_tag, sizeof(open_tag), "<%s>", tag);
    snprintf(close_tag, sizeof(close_tag), "</%s>", tag);
    const char *s = strstr(line, open_tag);
    if (!s) return;
    s += strlen(open_tag);
    const char *e = strstr(s, close_tag);
    if (!e) return;
    char buf[64];
    size_t len = (size_t)(e - s);
    if (len >= sizeof(buf)) len = sizeof(buf) - 1;
    memcpy(buf, s, len);
    buf[len] = '\0';
    *out = strtod(buf, NULL);
}

static void extract_tag_str(const char *line, const char *tag, char *out, size_t outsz) {
    char open_tag[32], close_tag[32];
    snprintf(open_tag, sizeof(open_tag), "<%s>", tag);
    snprintf(close_tag, sizeof(close_tag), "</%s>", tag);
    const char *s = strstr(line, open_tag);
    if (!s) return;
    s += strlen(open_tag);
    const char *e = strstr(s, close_tag);
    if (!e) return;
    size_t len = (size_t)(e - s);
    if (len >= outsz) len = outsz - 1;
    memcpy(out, s, len);
    out[len] = '\0';
    char *p = out;
    while (*p == ' ') p++;
    if (p != out) memmove(out, p, strlen(p) + 1);
    size_t l2 = strlen(out);
    while (l2 > 0 && out[l2 - 1] == ' ') out[--l2] = '\0';
}

static void process_line(char *line, long line_off) {
    if (strstr(line, "<step>")) {
        extract_tag_int(line, "step", &global_step);
        return;
    }
    if (strstr(line, "<rra>")) {
        current_rra++;
        current_cf[0] = '\0';
        current_pdp_per_row = 1;
        if (current_rra < MAX_RRA) {
            rra_cf[current_rra][0] = '\0';
            rra_pdp_per_row[current_rra] = 1;
            rra_xff[current_rra] = 0.5;
        }
        return;
    }
    if (strstr(line, "<cf>") && current_cf[0] == '\0') {
        extract_tag_str(line, "cf", current_cf, sizeof(current_cf));
        if (current_rra >= 0 && current_rra < MAX_RRA)
            snprintf(rra_cf[current_rra], sizeof(rra_cf[current_rra]), "%s", current_cf);
        return;
    }
    if (strstr(line, "<pdp_per_row>")) {
        long v = 1;
        extract_tag_int(line, "pdp_per_row", &v);
        current_pdp_per_row = (int)v;
        if (current_rra >= 0 && current_rra < MAX_RRA) rra_pdp_per_row[current_rra] = (int)v;
        return;
    }
    if (strstr(line, "<xff>")) {
        double v = 0.5;
        extract_tag_double(line, "xff", &v);
        if (current_rra >= 0 && current_rra < MAX_RRA) rra_xff[current_rra] = v;
        return;
    }
    if (strstr(line, "<database>")) {
        in_database = 1;
        state_reset_all();
        return;
    }
    if (strstr(line, "</database>")) {
        for (int ds = 0; ds < MAX_DS; ds++) {
            if (!ds_fixable[ds]) continue;
            DsState *st = &state[ds];
            if (st->run_active) resolve_run(current_rra, ds, st, 0, NAN, 0, current_rra == 0);
        }
        in_database = 0;
        return;
    }
    if (!in_database) return;
    if (!strstr(line, "<row>")) return;

    char *slash = strchr(line, '/');
    if (!slash) return;
    time_t ts = (time_t)strtol(slash + 1, NULL, 10);

    char *cur = line;
    for (int ds = 0; ds < MAX_DS; ds++) {
        char *vs = strstr(cur, "<v>");
        if (!vs) return;
        vs += 3;
        char *ve = strstr(vs, "</v>");
        if (!ve) return;
        long off = line_off + (vs - line);
        int len = (int)(ve - vs);

        int is_nan = (len == 3 && strncmp(vs, "NaN", 3) == 0);
        double val = is_nan ? NAN : strtod(vs, NULL);
        cur = ve + 4;

        if (!ds_fixable[ds]) continue;

        if (current_rra == 0) {
            handle_raw_row(ds, ts, val, is_nan, off, len);
        } else {
            handle_other_rra_row(current_rra, ds, ts, val, is_nan, off, len, current_pdp_per_row);
        }
    }
}

/* ---------------------------------------------------------------------
 * helpers
 * --------------------------------------------------------------------- */

static void fmt_time(time_t t, char *buf, size_t n) {
    struct tm tmv;
    localtime_r(&t, &tmv);
    strftime(buf, n, "%Y-%m-%d %H:%M:%S", &tmv);
}

static void fmt_duration(time_t secs, char *buf, size_t n) {
    long s = (long)secs;
    long d = s / 86400; s %= 86400;
    long h = s / 3600;  s %= 3600;
    long m = s / 60;
    if (d > 0)      snprintf(buf, n, "%ldd %ldh %ldm", d, h, m);
    else if (h > 0) snprintf(buf, n, "%ldh %ldm", h, m);
    else            snprintf(buf, n, "%ldm", m);
}

static int parse_backtime(const char *spec, long *seconds_out) {
    char unit = 0;
    long num = 0;
    int n = sscanf(spec, "%ld%c", &num, &unit);
    if (n != 2 || num <= 0) return -1;
    if (unit == 'd' || unit == 'D')      *seconds_out = num * 86400L;
    else if (unit == 'h' || unit == 'H') *seconds_out = num * 3600L;
    else return -1;
    return 0;
}

static void print_help(const char *prog) {
    printf(
"%s - find and optionally fix bad samples in a weather RRD database\n"
"\n"
"Usage:\n"
"  %s -f <rrd-file> -b <Nd|Nh> [-w] [-d]\n"
"  %s -h\n"
"\n"
"Options:\n"
"  -h            Show this help and exit.\n"
"  -f <file>     Full path to the RRD database to analyze/fix.\n"
"  -b <Nd|Nh>    How far back to look, e.g. '7d' (7 days) or '48h' (48 hours).\n"
"                The window is [now - N, now]; both ends are wall-clock time.\n"
"  -w            Commit fixes: write corrected values back to the RRD.\n"
"                Without -w, the program only reports what it finds.\n"
"  -d            Debug output: show every bad row and every consolidated\n"
"                archive row touched, in addition to the normal summary.\n"
"\n"
"What it does:\n"
"  temp/humi/bmpr sometimes record NaN when a sensor read fails, or - worse\n"
"  - an implausible numeric value (e.g. a brief drop to -2 C when the\n"
"  surrounding readings are around 25 C). This tool finds both kinds of bad\n"
"  sample in the raw archive by comparing each reading to a short rolling\n"
"  average of recent good readings, and, with -w, linearly interpolates\n"
"  across the bad run using the last good value before it and the first\n"
"  good value after it.\n"
"\n"
"  Because RRD keeps several consolidated archives (hourly/daily AVERAGE,\n"
"  MIN, MAX), a bad raw sample also corrupts those archives - and unlike a\n"
"  literal NaN, an implausible value does NOT get excluded from that\n"
"  consolidation, so the archive silently ends up wrong without itself\n"
"  containing a NaN. To fix this properly, every consolidated row is\n"
"  recomputed directly from the corrected raw data, rather than merely\n"
"  patched wherever it happens to already read NaN. If a row's time span\n"
"  has aged out of the raw archive's retention, it falls back to a plain\n"
"  same-archive interpolation instead (an approximation, and only able to\n"
"  catch literal NaN at that point).\n"
"\n"
"  'dayt' (a day/night 0/1 flag) is never analyzed or touched.\n"
"\n"
"  Before writing, the original file is copied to '<file>.bak'; the fixed\n"
"  database then atomically replaces the original.\n"
"\n"
"Implausible-value thresholds (vs. a %d-sample rolling average), tune at\n"
"the top of the source if needed:\n"
"  temp: %.1f C     humi: %.1f points     bmpr: %.1f Pa\n"
"\n"
"Examples:\n"
"  %s -f /home/pi/pi-ws01/rrd/weather.rrd -b 7d\n"
"  %s -f /home/pi/pi-ws01/rrd/weather.rrd -b 48h\n"
"  %s -f /home/pi/pi-ws01/rrd/weather.rrd -b 7d -w\n"
"  %s -f /home/pi/pi-ws01/rrd/weather.rrd -b 7d -w -d\n",
    prog, prog, prog, N_BASELINE, THRESH_TEMP, THRESH_HUMI, THRESH_BMPR,
    prog, prog, prog, prog);
}

static int copy_file(const char *src, const char *dst) {
    FILE *in = fopen(src, "rb");
    if (!in) return -1;
    FILE *out = fopen(dst, "wb");
    if (!out) { fclose(in); return -1; }
    char buf[65536];
    size_t n;
    int rc = 0;
    while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
        if (fwrite(buf, 1, n, out) != n) { rc = -1; break; }
    }
    if (ferror(in)) rc = -1;
    fclose(in);
    fclose(out);
    return rc;
}

static int patch_cmp(const void *a, const void *b) {
    const Patch *pa = a, *pb = b;
    if (pa->off < pb->off) return -1;
    if (pa->off > pb->off) return 1;
    return 0;
}

int main(int argc, char **argv) {
    char *rrd_file = NULL;
    char *back_spec = NULL;
    int opt;

    for (int i = 0; i < MAX_RRA; i++) rra_xff[i] = 0.5;

    while ((opt = getopt(argc, argv, "hf:b:wd")) != -1) {
        switch (opt) {
            case 'h': print_help(argv[0]); return 0;
            case 'f': rrd_file = optarg; break;
            case 'b': back_spec = optarg; break;
            case 'w': opt_write = 1; break;
            case 'd': opt_debug = 1; break;
            default:
                fprintf(stderr, "Try '%s -h' for help.\n", argv[0]);
                return 1;
        }
    }

    if (!rrd_file || !back_spec) {
        fprintf(stderr, "Error: -f and -b are both required.\n");
        fprintf(stderr, "Try '%s -h' for help.\n", argv[0]);
        return 1;
    }

    long lookback_secs;
    if (parse_backtime(back_spec, &lookback_secs) != 0) {
        fprintf(stderr, "Error: invalid -b value '%s' (expected e.g. '7d' or '48h').\n", back_spec);
        return 1;
    }

    struct stat st_check;
    if (stat(rrd_file, &st_check) != 0) {
        fprintf(stderr, "Error: cannot access '%s': %s\n", rrd_file, strerror(errno));
        return 1;
    }

    time_t now = time(NULL);
    win_end = now;
    win_start = now - lookback_secs;

    char win_buf1[32], win_buf2[32];
    fmt_time(win_start, win_buf1, sizeof(win_buf1));
    fmt_time(win_end, win_buf2, sizeof(win_buf2));
    printf("fix-weatherdb: %s\n", rrd_file);
    printf("Checking window: %s -> %s (back %s)\n\n", win_buf1, win_buf2, back_spec);

    char xml_tmp[] = "/tmp/fix-weatherdb-dump-XXXXXX";
    int xml_fd = mkstemp(xml_tmp);
    if (xml_fd < 0) { perror("mkstemp"); return 1; }
    close(xml_fd);

    char *dump_argv[] = { (char*)"dump", (char*)"-n", rrd_file, xml_tmp };
    rrd_clear_error();
    if (rrd_dump(4, dump_argv) != 0) {
        fprintf(stderr, "Error: rrd_dump failed: %s\n", rrd_get_error());
        unlink(xml_tmp);
        return 1;
    }

    FILE *xf = fopen(xml_tmp, "rb");
    if (!xf) { perror("fopen xml"); unlink(xml_tmp); return 1; }
    fseek(xf, 0, SEEK_END);
    long fsize = ftell(xf);
    fseek(xf, 0, SEEK_SET);
    char *filebuf = malloc(fsize + 1);
    if (fread(filebuf, 1, fsize, xf) != (size_t)fsize) {
        fprintf(stderr, "Error: short read on dump file\n");
        fclose(xf); unlink(xml_tmp); return 1;
    }
    filebuf[fsize] = '\0';
    fclose(xf);

    char *p = filebuf;
    while (*p) {
        char *eol = strchr(p, '\n');
        char saved = 0;
        if (eol) { saved = *eol; *eol = '\0'; }
        long off = p - filebuf;
        process_line(p, off);
        if (eol) { *eol = saved; p = eol + 1; }
        else break;
    }

    long reported = 0;
    for (long i = 0; i < gap_count; i++) {
        GapEvent *g = &gaps[i];
        if (!opt_debug && g->rra != 0) continue;
        reported++;

        char t1[32], t2[32], dur[32];
        fmt_time(g->t_first_nan, t1, sizeof(t1));
        fmt_time(g->t_last_nan, t2, sizeof(t2));
        fmt_duration(g->t_last_nan - g->t_first_nan, dur, sizeof(dur));

        char composition[64];
        if (g->rra == 0)
            snprintf(composition, sizeof(composition), ": %ld NaN + %ld implausible",
                     g->n_nan, g->n_outlier);
        else
            composition[0] = '\0';

        if (opt_debug) {
            printf("[%s] DS %-4s %s: gap %s -> %s (%s, %ld samples%s)\n",
                   rra_label(g->rra), ds_name[g->ds],
                   g->bounded ? (opt_write ? "fixed" : "found") : "UNRESOLVED",
                   t1, t2, dur, g->n_points, composition);
        } else {
            printf("DS %-4s: gap %s -> %s (%s, %ld samples%s)%s\n",
                   ds_name[g->ds], t1, t2, dur, g->n_points, composition,
                   g->bounded ? "" : "  [unresolved: no bounding data on one side, not fixed]");
        }

        if (g->bounded) {
            char tb[32], ta[32];
            fmt_time(g->t_before, tb, sizeof(tb));
            fmt_time(g->t_after, ta, sizeof(ta));
            printf("  fix: %s=%.4f  ->  %s=%.4f  (%ld points%s)\n",
                   tb, g->v_before, ta, g->v_after, g->n_points,
                   g->fixed ? ", written" : "");
        }
    }
    if (reported == 0) {
        printf("No bad samples found in the requested window.\n");
    }

    if (gap_count > 0 || opt_debug) {
        int any_summary = 0;
        for (int ds = 0; ds < MAX_DS; ds++) {
            if (!ds_fixable[ds]) continue;
            long total = 0;
            for (int r = 0; r <= current_rra; r++) total += fixed_points[ds][r];
            if (total == 0) continue;
            if (!any_summary) { printf("\nFix summary (data points written per archive):\n"); any_summary = 1; }
            printf("  DS %-4s: ", ds_name[ds]);
            for (int r = 0; r <= current_rra; r++) {
                if (fixed_points[ds][r] == 0) continue;
                printf("RRA%d=%ld  ", r, fixed_points[ds][r]);
            }
            printf("\n");
        }
    }

    if (opt_write && patch_count > 0) {
        char xml_fixed[] = "/tmp/fix-weatherdb-fixed-XXXXXX";
        int fixed_fd = mkstemp(xml_fixed);
        if (fixed_fd < 0) { perror("mkstemp fixed"); goto cleanup; }
        FILE *of = fdopen(fixed_fd, "wb");

        qsort(patches, patch_count, sizeof(Patch), patch_cmp);

        long cursor = 0;
        for (long i = 0; i < patch_count; i++) {
            Patch *pt = &patches[i];
            fwrite(filebuf + cursor, 1, pt->off - cursor, of);
            fwrite(pt->text, 1, strlen(pt->text), of);
            cursor = pt->off + pt->old_len;
        }
        fwrite(filebuf + cursor, 1, fsize - cursor, of);
        fclose(of);

        char *rrd_dir_copy = strdup(rrd_file);
        char *dirpart = dirname(rrd_dir_copy);
        char rrd_tmp[PATH_MAX];
        snprintf(rrd_tmp, sizeof(rrd_tmp), "%s/.fix-weatherdb-tmp-XXXXXX", dirpart);
        int rrd_tmp_fd = mkstemp(rrd_tmp);
        if (rrd_tmp_fd < 0) {
            perror("mkstemp rrd tmp");
            free(rrd_dir_copy);
            unlink(xml_fixed);
            goto cleanup;
        }
        close(rrd_tmp_fd);
        free(rrd_dir_copy);

        char *restore_argv[] = { (char*)"restore", (char*)"-f", xml_fixed, rrd_tmp };
        rrd_clear_error();
        if (rrd_restore(4, restore_argv) != 0) {
            fprintf(stderr, "Error: rrd_restore failed: %s\n", rrd_get_error());
            unlink(xml_fixed);
            unlink(rrd_tmp);
            goto cleanup;
        }
        unlink(xml_fixed);

        char bak_path[PATH_MAX];
        snprintf(bak_path, sizeof(bak_path), "%s.bak", rrd_file);
        if (copy_file(rrd_file, bak_path) != 0) {
            fprintf(stderr, "Error: could not create backup '%s': %s\n", bak_path, strerror(errno));
            unlink(rrd_tmp);
            goto cleanup;
        }

        if (rename(rrd_tmp, rrd_file) != 0) {
            fprintf(stderr, "Error: could not replace '%s': %s\n", rrd_file, strerror(errno));
            fprintf(stderr, "Fixed database is left at '%s' - please move it into place manually.\n", rrd_tmp);
            goto cleanup;
        }

        printf("\nBackup written to %s\n", bak_path);
        printf("%s updated (%ld total values patched across all archives).\n", rrd_file, patch_count);
    } else if (opt_write) {
        printf("\nNothing to write (no fixable bad samples in the requested window).\n");
    } else if (gap_count > 0) {
        printf("\nRun again with -w to write these fixes to the database.\n");
    }

cleanup:
    unlink(xml_tmp);
    free(filebuf);
    return 0;
}
