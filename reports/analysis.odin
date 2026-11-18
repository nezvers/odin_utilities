package reports

// What can be said about the numbers of a report without knowing what they measure: which side of a ratio is better, how a column is spread, how
// far two reports differ. The renderers (the digest above all) and the comparison are built on it.

import "core:math"

DEFAULT_BAND :: 0.05            // a ratio within 5% of 1 is the same

Verdict :: enum u8 {
    NONE,               // nothing to say (no direction, no number)
    BETTER,
    WORSE,
    SAME,
}

// A ratio (this divided by the reference, 1 is equal) against the direction of its column, with a band around 1 that counts as the same.
RatioVerdict :: proc(ratio: f64, better: Better, band: f64 = DEFAULT_BAND) -> Verdict {
    if better == .NONE || math.is_nan(ratio) || math.is_inf(ratio) || ratio <= 0 { return .NONE }
    low: f64 = 1 - band
    high: f64 = 1 + band
    switch {
    case ratio < low:
        return .BETTER if better == .LOWER else .WORSE
    case ratio > high:
        return .WORSE if better == .LOWER else .BETTER
    }
    return .SAME
}

ColumnStats :: struct {
    count: int,                 // cells with a number
    minimum: f64,
    maximum: f64,
    mean: f64,
    geometric_mean: f64,        // of the positive numbers: the fair average of ratios (0 when none is positive)
    better: int,                // ratio columns: how many rows are better / worse / the same (see RatioVerdict)
    worse: int,
    same: int,
    best_row: int,              // the row with the best / worst number for the direction of the column, -1 when there is none
    worst_row: int,
}

// The numbers of one column of a table. For a ratio column the verdicts are counted with `band`.
TableColumnStats :: proc(table: ^Table, column: int, band: f64 = DEFAULT_BAND) -> ColumnStats {
    stats: ColumnStats = {best_row = -1, worst_row = -1, minimum = math.INF_F64, maximum = -math.INF_F64}
    spec: Column = table.columns[column]
    log_sum: f64
    positive: int
    sum: f64
    best: f64
    worst: f64
    for row in 0 ..< TableRowCount(table) {
        cell: ^Cell = TableCell(table, row, column)
        if !cell.has_number || math.is_nan(cell.number) { continue }
        value: f64 = cell.number
        stats.count += 1
        sum += value
        stats.minimum = min(stats.minimum, value)
        stats.maximum = max(stats.maximum, value)
        if value > 0 {
            log_sum += math.ln(value)
            positive += 1
        }
        if spec.kind == .RATIO {
            switch RatioVerdict(value, spec.better, band) {
            case .BETTER:
                stats.better += 1
            case .WORSE:
                stats.worse += 1
            case .SAME:
                stats.same += 1
            case .NONE:
            }
        }
        // best and worst by the direction of the column (lower is better unless it says otherwise)
        lower_is_good: bool = spec.better != .HIGHER
        if stats.best_row < 0 || (value < best if lower_is_good else value > best) {
            stats.best_row = row
            best = value
        }
        if stats.worst_row < 0 || (value > worst if lower_is_good else value < worst) {
            stats.worst_row = row
            worst = value
        }
    }
    if stats.count > 0 { stats.mean = sum / f64(stats.count) }
    if positive > 0 { stats.geometric_mean = math.exp(log_sum / f64(positive)) }
    if stats.count == 0 {
        stats.minimum, stats.maximum = 0, 0
    }
    return stats
}

// The text of the first cell of a row: what names it.
TableRowLabel :: proc(table: ^Table, row: int) -> string {
    cell: ^Cell = TableCell(table, row, 0)
    if cell.text != "" { return cell.text }
    return FormatNumber(cell.number) if cell.has_number else ""
}
