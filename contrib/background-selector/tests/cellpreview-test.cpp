// Tests the real parser and CPU snapshot path without opening a window.
// AMBIENT_CELLS_TEST grants this test access; it adds no production API.
#include <QGuiApplication>
#include <QTemporaryDir>
#include <QFile>
#include <iostream>
#include <stdexcept>
#define AMBIENT_CELLS_TEST
#include "../live-preview/native/AmbientCells/cellpreview.cpp"

struct ExpectedCell { int x, y; QString ch; QRgb color; };
static void require(bool value, const char* label) {
    if (!value) throw std::runtime_error(label);
}
static QString jsonString(const QString& value) {
    QString text(QChar(u'"'));
    for (QChar c : value) {
        if (c == u'"' || c == u'\\') { text += u'\\'; text += c; }
        else if (c.unicode() < 0x20)
            text += QStringLiteral("\\u%1").arg(uint(c.unicode()), 4, 16, QChar(u'0'));
        else text += c;
    }
    return text + u'"';
}
static QString colorName(QRgb color) { return QColor::fromRgb(color).name(); }
static QString cellsText(const QVector<ExpectedCell>& cells) {
    QString text;
    for (const auto& cell : cells)
        text += QStringLiteral("%1,%2,%3,%4;").arg(cell.x).arg(cell.y).arg(cell.ch).arg(colorName(cell.color));
    return text;
}
static QString runsText(const QVector<ExpectedCell>& cells) {
    QString text;
    for (qsizetype start = 0; start < cells.size();) {
        qsizetype end = start + 1;
        while (end < cells.size() && cells[end].y == cells[start].y &&
               cells[end].x == cells[end - 1].x + 1 && cells[end].color == cells[start].color) ++end;
        QString glyphs;
        for (qsizetype i = start; i < end; ++i) glyphs += cells[i].ch;
        text += QStringLiteral("%1,%2,%3,%4,%5;").arg(cells[start].x).arg(cells[start].y)
                    .arg(colorName(cells[start].color)).arg(end - start).arg(glyphs);
        start = end;
    }
    return text;
}
static QString frame(const QString& key, const QString& payload, const QString& effect = "neon-city") {
    return "{\"fx\":" + jsonString(effect) + ",\"" + key + "\":" + jsonString(payload)
        + ",\"w\":40,\"h\":10,\"volume\":0.25}";
}

struct CellPreviewTest {
    static void check(const CellPreview& view, const QVector<ExpectedCell>& expected) {
        require(view.m_parsed.size() == expected.size(), "parsed cell count");
        for (qsizetype i = 0; i < expected.size(); ++i) {
            const auto& got = view.m_parsed[i]; const auto& want = expected[i];
            require(got.x == want.x && got.y == want.y, "cell coordinates");
            require(got.ch == want.ch, "cell Unicode character or JSON escape");
            require(got.color == want.color, "cell color");
            const auto code = want.ch.toUcs4();
            require(code.size() == 1 && got.code == code[0], "single Unicode code point");
        }
    }
    static void parser() {
        // Control escapes match the daemon's \u00XX form. Comma and semicolon
        // are tested separately on runs: they delimit the legacy cells format.
        const QVector<QString> glyphs = {"A", QStringLiteral("é"), QStringLiteral("界"), QStringLiteral("🚀"), QStringLiteral("█"), QStringLiteral("▌"), QStringLiteral("▬"), QStringLiteral("▪"), " ", "\"", "\\", QString(QChar(0)), "\n"};
        quint32 random = 0x5eed1234;
        auto next = [&] { random = random * 1664525u + 1013904223u; return random; };
        CellPreview plain, perCell, runs;
        qsizetype checked = 0;
        for (int iteration = 0; iteration < 200; ++iteration) {
            QVector<ExpectedCell> expected;
            for (int i = 0; i < 160; ++i)
                expected.push_back({i % 40, i / 40, glyphs[next() % glyphs.size()],
                                    qRgb((i / 7) % 3 * 70, (iteration * 11) % 256, (i / 7) % 2 * 120)});
            // All three inputs must decode to the independently held cells.
            plain.setCells(cellsText(expected));
            perCell.setFrameLine(frame("cells", cellsText(expected)));
            runs.setFrameLine(frame("runs", runsText(expected)));
            check(plain, expected); check(perCell, expected); check(runs, expected);
            checked += expected.size();
        }
        const QVector<ExpectedCell> delimiters = {{0, 0, ",", qRgb(3, 5, 7)}, {1, 0, ";", qRgb(3, 5, 7)}};
        runs.setFrameLine(frame("runs", runsText(delimiters))); check(runs, delimiters);
        const QVector<ExpectedCell> fallback = {{0, 0, "A", qRgb(18, 52, 86)}, {1, 0, QStringLiteral("🚀"), qRgb(18, 52, 86)}};
        perCell.setFrameLine(QStringLiteral("{\"fx\":\"other-effect\",\"cells\":\"0,0,\\u0041,#123456;1,0,\\ud83d\\ude80,#123456;\",\"w\":40}"));
        check(perCell, fallback);
        runs.setFrameLine(QStringLiteral("{\"fx\":\"other-effect\",\"runs\":\"0,0,#123456,2,\\u0041\\ud83d\\ude80;\",\"w\":40}"));
        check(runs, fallback);
        // An incomplete envelope cannot replace the previous complete frame.
        perCell.setFrameLine("{\"fx\":\"other-effect\",\"cells\":\"0,0,A"); check(perCell, fallback);
        perCell.setFrameLine("{\"status\":\"ready\"}"); check(perCell, fallback);
        // A complete but broken run clears its partial parse; the next effect recovers.
        runs.setFrameLine(frame("runs", "0,0,#123456,4,AB")); check(runs, {});
        runs.setFrameLine(frame("runs", "0,0,#123456,2147483647,A")); check(runs, {});
        runs.setFrameLine(frame("runs", runsText(fallback), "circuit-run")); check(runs, fallback);
        perCell.setFrameLine(frame("cells", "incomplete-record")); check(perCell, {});
        perCell.setFrameLine(frame("cells", cellsText(fallback), "circuit-run")); check(perCell, fallback);
        perCell.setFrameLine(frame("cells", "")); check(perCell, {});
        runs.setFrameLine(frame("runs", "")); check(runs, {});
        std::cout << "PARSER_GATE " << checked << " expected cells x3 paths; Unicode, escapes, malformed and effect changes OK\n";
    }
    static void snapshots() {
        const QVector<ExpectedCell> expected = {{0, 0, "A", qRgb(255, 70, 30)}, {1, 0, QStringLiteral("界"), qRgb(40, 190, 220)},
            {2, 0, QStringLiteral("🚀"), qRgb(180, 20, 210)}, {3, 0, QStringLiteral("█"), qRgb(70, 230, 110)}, {0, 1, QStringLiteral("▌"), qRgb(9, 17, 220)},
            {1, 1, QStringLiteral("▬"), qRgb(240, 220, 20)}, {2, 1, QStringLiteral("▪"), qRgb(190, 30, 55)}, {3, 1, " ", qRgb(255, 255, 255)}};
        CellPreview a, b;
        a.setSize(QSizeF(96, 48)); b.setSize(a.size());
        a.setFrameLine(frame("cells", cellsText(expected))); b.setFrameLine(frame("runs", runsText(expected)));
        int compared = 0;
        QTemporaryDir output; require(output.isValid(), "snapshot temporary directory");
        for (qreal dpr : {1.0, 1.5, 2.0}) for (qreal opacity : {1.0, 0.43}) for (qreal skew : {0.0, -9.25, 9.25}) {
            const QVariantMap metrics = {{"cw", 11.25}, {"ch", 17.5}, {"x", 3.375}, {"y", 0.625}, {"font", 12.0}};
            a.setMetrics(metrics); b.setMetrics(metrics); a.setCellOpacity(opacity); b.setCellOpacity(opacity);
            a.setSkew(skew); b.setSkew(skew);
            const QImage aa = a.render(dpr), bb = b.render(dpr);
            require(!aa.isNull() && aa == bb, "cells/runs CPU snapshots differ");
            const auto blank = QRgb(CellPreview::Background);
            bool lit = false;
            for (int y = 0; y < aa.height(); ++y) for (int x = 0; x < aa.width(); ++x)
                lit = lit || (aa.pixel(x, y) != blank && qAlpha(aa.pixel(x, y)) != 0);
            require(lit, "snapshot must contain visible marks");
            // save() uses the DPR prepared by render(), without needing a window.
            const QString path = output.filePath(QStringLiteral("frame-%1.png").arg(compared));
            require(a.save(path), "CellPreview.save failed");
            const QImage loaded = QImage(path).convertToFormat(aa.format());
            require(loaded.size() == aa.size(), "saved snapshot size differs");
            for (int y = 0; y < aa.height(); ++y) for (int x = 0; x < aa.width(); ++x)
                require(loaded.pixel(x, y) == aa.pixel(x, y), "saved snapshot pixel differs");
            ++compared;
        }
        std::cout << "SNAPSHOT_GATE " << compared << " CPU/save pairs exact; DPR, alpha, skew and fractional metrics OK\n";
    }
};
int main(int argc, char** argv) {
    QGuiApplication app(argc, argv);
    try { CellPreviewTest::parser(); CellPreviewTest::snapshots(); }
    catch (const std::exception& error) { std::cerr << "FAIL: " << error.what() << '\n'; return 1; }
    return 0;
}
