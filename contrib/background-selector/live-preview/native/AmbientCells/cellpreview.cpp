// Draws a preview frame from native code. The carousel loads this if it can
// and keeps its Canvas otherwise, so a shell built on another Qt only loses speed.
//
// The GPU draws the cells: each one is a quad over a glyph atlas, so a frame
// sends a few hundred kilobytes of vertices instead of a full-size image.
// The same placement also paints into an image on the CPU, for save() and for
// a scene graph without a GPU.
#include <QElapsedTimer>
#include <QHash>
#include <QImage>
#include <QMetaObject>
#include <QPainter>
#include <QPainterPath>
#include <QPointer>
#include <QPolygonF>
#include <QProcess>
#include <QQmlExtensionPlugin>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSGGeometryNode>
#include <QSGImageNode>
#include <QSGMaterial>
#include <QSGMaterialShader>
#include <QSGRendererInterface>
#include <QSGTexture>
#include <QVariantMap>
#include <QVector>
#include <QtQml/qqml.h>
#include <algorithm>
#include <array>
#include <cctype>
#include <climits>
#include <cmath>
#include <cstring>
#include <utility>

// The daemon sends #rrggbb; anything else goes through QColor.
static QRgb parseColor(QStringView style) {
    auto hex = [](char16_t c) -> int {
        if (c >= u'0' && c <= u'9') return c - u'0';
        if (c >= u'a' && c <= u'f') return c - u'a' + 10;
        if (c >= u'A' && c <= u'F') return c - u'A' + 10;
        return -1;
    };
    if (style.size() == 7 && style[0] == u'#') {
        QRgb rgb = 0;
        bool ok = true;
        for (int i = 1; i < 7 && ok; ++i) {
            const int digit = hex(style[i].unicode());
            ok = digit >= 0;
            rgb = rgb << 4 | QRgb(digit);
        }
        if (ok) return 0xff000000 | rgb;
    }
    return QColor::fromString(style).rgba();
}

namespace {

struct CellVertex {
    float x, y, u, v;
    uchar r, g, b, a;
};

const QSGGeometry::AttributeSet& cellAttributes() {
    static const QSGGeometry::Attribute attributes[] = {
        QSGGeometry::Attribute::createWithAttributeType(0, 2, QSGGeometry::FloatType, QSGGeometry::PositionAttribute),
        QSGGeometry::Attribute::createWithAttributeType(1, 2, QSGGeometry::FloatType, QSGGeometry::TexCoordAttribute),
        QSGGeometry::Attribute::createWithAttributeType(2, 4, QSGGeometry::UnsignedByteType, QSGGeometry::ColorAttribute),
    };
    static const QSGGeometry::AttributeSet set = {3, sizeof(CellVertex), attributes};
    return set;
}

// Cells blend over what is below; the skew mask keeps the destination where
// it is set, as QPainter's DestinationIn does.
class CellMaterial : public QSGMaterial {
public:
    explicit CellMaterial(bool mask) : m_mask(mask) { setFlag(Blending); }
    QSGMaterialType* type() const override {
        static QSGMaterialType cells, masks;
        return m_mask ? &masks : &cells;
    }
    QSGMaterialShader* createShader(QSGRendererInterface::RenderMode) const override;
    int compare(const QSGMaterial* other) const override {
        const auto theirs = static_cast<const CellMaterial*>(other)->texture;
        return texture == theirs ? 0 : (std::less<QSGTexture*>{}(texture, theirs) ? -1 : 1);
    }
    QSGTexture* texture = nullptr;

private:
    bool m_mask;
};

class CellShader : public QSGMaterialShader {
public:
    explicit CellShader(bool mask) {
        setShaderFileName(VertexStage, QStringLiteral(":/ambientcells/cells.vert.qsb"));
        setShaderFileName(FragmentStage, QStringLiteral(":/ambientcells/cells.frag.qsb"));
        if (mask) setFlag(UpdatesGraphicsPipelineState);
    }
    bool updateUniformData(RenderState& state, QSGMaterial*, QSGMaterial*) override {
        QByteArray* buffer = state.uniformData();
        bool changed = false;
        if (state.isMatrixDirty()) {
            const QMatrix4x4 matrix = state.combinedMatrix();
            std::memcpy(buffer->data(), matrix.constData(), 64);
            changed = true;
        }
        if (state.isOpacityDirty()) {
            const float opacity = state.opacity();
            std::memcpy(buffer->data() + 64, &opacity, 4);
            changed = true;
        }
        return changed;
    }
    void updateSampledImage(RenderState& state, int binding, QSGTexture** texture, QSGMaterial* material, QSGMaterial*) override {
        if (binding != 1) return;
        QSGTexture* own = static_cast<CellMaterial*>(material)->texture;
        // A material uploads its own textures; the renderer only binds them.
        own->commitTextureOperations(state.rhi(), state.resourceUpdateBatch());
        *texture = own;
    }
    bool updateGraphicsPipelineState(RenderState&, GraphicsPipelineState* state, QSGMaterial*, QSGMaterial*) override {
        state->blendEnable = true;
        state->srcColor = GraphicsPipelineState::Zero;
        state->dstColor = GraphicsPipelineState::SrcAlpha;
        state->separateBlendFactors = false;
        return true;
    }
};

QSGMaterialShader* CellMaterial::createShader(QSGRendererInterface::RenderMode) const { return new CellShader(m_mask); }

class CellNode : public QSGNode {
public:
    CellNode() {
        cells = newGeometryNode(false);
        appendChildNode(cells);
        mask = newGeometryNode(true);
    }
    ~CellNode() override {
        if (!mask->parent()) delete mask;
        delete atlas;
        delete maskTexture;
    }
    static void setTexture(QSGGeometryNode* node, QSGTexture* texture) {
        static_cast<CellMaterial*>(node->material())->texture = texture;
        node->markDirty(QSGNode::DirtyMaterial);
    }
    QSGGeometryNode* cells;
    QSGGeometryNode* mask;
    QSGTexture* atlas = nullptr;
    QSGTexture* maskTexture = nullptr;
    int atlasVersion = -1;
    QImage maskImage;

private:
    static QSGGeometryNode* newGeometryNode(bool mask) {
        auto node = new QSGGeometryNode;
        auto geometry = new QSGGeometry(cellAttributes(), 0, 0, QSGGeometry::UnsignedIntType);
        geometry->setDrawingMode(QSGGeometry::DrawTriangles);
        geometry->setVertexDataPattern(QSGGeometry::StreamPattern);
        geometry->setIndexDataPattern(QSGGeometry::StreamPattern);
        node->setGeometry(geometry);
        node->setFlag(QSGNode::OwnsGeometry);
        node->setMaterial(new CellMaterial(mask));
        node->setFlag(QSGNode::OwnsMaterial);
        return node;
    }
};

} // namespace

class CellPreview : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(qreal skew READ skew WRITE setSkew NOTIFY skewChanged)
    Q_PROPERTY(QString cells READ cells WRITE setCells NOTIFY cellsChanged)
    Q_PROPERTY(QVariantMap metrics READ metrics WRITE setMetrics NOTIFY metricsChanged)
    Q_PROPERTY(qreal cellOpacity READ cellOpacity WRITE setCellOpacity NOTIFY cellOpacityChanged)

    // What a cell draws, worked out once when the frame arrives.
    enum Kind : quint8 { Glyph, Block, Bar, HalfBlock, Dot, Blank };
    struct Cell {
        int x, y;
        QStringView ch;
        QRgb color;
        Kind kind;
        char32_t code; // the character as one code point, 0 when it is not one
    };
    struct Coverage {
        QRect bounds;
        QPoint offset; // of the mask within the bounds, in device pixels
        QImage mask;   // the set pixels only
        QPoint atlas{-1, -1};
    };
    static constexpr QRgb Background = 0xff07070d;
    static constexpr int MaxMaskBytes = 8 * 1024 * 1024;
    static constexpr int AtlasWidth = 1024;
    static constexpr int MaxAtlasHeight = 4096;

    qreal m_skew = 0;
    double m_lineMs = 0;
    // The cells of the frame and the string that holds them: a daemon line is
    // kept whole, implicitly shared, so taking a frame copies nothing.
    QString m_source;
    QStringView m_cells;
    bool m_cellsJson = false; // m_cells is still JSON-escaped
    bool m_cellsRuns = false; // m_cells holds runs, not one record per cell
    QVariantMap m_metrics;
    qreal m_cellOpacity = 1;
    QVector<Cell> m_parsed;
    // Keyed by code point and sub-pixel offset: a string key cost more than the blit.
    QHash<quint64, Coverage> m_coverage;
    qsizetype m_coverageBytes = 0;
    QFont m_font;
    int m_fontPixel = -1;
    qreal m_dpr = -1;
    // Glyphs the GPU has seen, packed in shelves; a solid block sits at the origin.
    QImage m_atlas;
    int m_atlasVersion = 0;
    QPoint m_shelf;
    int m_shelfHeight = 0;
    QVector<CellVertex> m_vertices;
    // Device pixels of a column or row: where a glyph starts, and the spans of
    // a full cell, a part of one (half block across, bar down) and a dot.
    struct Span { int from, to; };
    struct Line { qreal start, fraction; int sub; Span full, part, dot; };
    QVector<Line> m_columns, m_rows;
    QImage m_mask;
    qreal m_maskSkew = 0;

public:
    explicit CellPreview(QQuickItem* parent = nullptr) : QQuickItem(parent) { setFlag(ItemHasContents); }
    qreal skew() const { return m_skew; }
    void setSkew(qreal value) {
        if (value == m_skew) return;
        m_skew = value;
        emit skewChanged();
        update();
    }
    QString cells() const {
        if (!m_cellsRuns) return m_cellsJson ? unescape(m_cells) : m_cells.toString();
        QString text;
        for (const Cell& cell : m_parsed)
            text += QStringLiteral("%1,%2,%3,%4;").arg(cell.x).arg(cell.y).arg(cell.ch).arg(QColor::fromRgb(cell.color).name());
        return text;
    }
    QVariantMap metrics() const { return m_metrics; }
    qreal cellOpacity() const { return m_cellOpacity; }

    // A preview daemon line as it arrived, so the shell does not run a JSON
    // parser over every frame: only the cells string is taken out of it.
    Q_INVOKABLE void setFrameLine(const QString& line) {
        QElapsedTimer timer;
        timer.start();
        // Shells that ask for it get runs of cells instead of one record each.
        // The key follows the effect's name, and the size fields close the
        // line: neither search has to cross the cells themselves.
        qsizetype start = -1;
        bool runs = false;
        if (line.startsWith(u"{\"fx\":\"")) {
            const qsizetype quote = line.indexOf(u'"', 7);
            const QStringView after = quote > 0 ? QStringView{line}.sliced(quote) : QStringView();
            if (after.startsWith(u"\",\"cells\":\"")) start = quote + 2;
            else if (after.startsWith(u"\",\"runs\":\"")) { start = quote + 2; runs = true; }
        }
        if (start < 0) {
            start = line.indexOf(u"\"cells\":\"");
            runs = start < 0;
            if (runs) start = line.indexOf(u"\"runs\":\"");
        }
        if (start < 0) return;
        const qsizetype from = start + (runs ? 8 : 9);
        // The size fields close the line: look for them from its end.
        const qsizetype end = line.lastIndexOf(u"\",\"w\":");
        if (end < from) return;
        const QStringView raw = QStringView{line}.sliced(from, end - from);
        if (!m_cellsJson || runs != m_cellsRuns || raw != m_cells) {
            // Escapes only ever stand for a cell's character, so the line splits
            // as it is; a field that needs more than that takes the slow way.
            m_source = line;
            const QStringView view = QStringView{m_source}.sliced(from, end - from);
            if (!(runs ? parseRuns(view, true) : parse(view, true))) {
                m_source = unescape(raw);
                if (!(runs ? parseRuns(m_source, false) : parse(m_source, false))) {
                    emit cellsChanged();
                    update();
                }
            }
        }
        m_lineMs = timer.nsecsElapsed() / 1e6;
    }

    void setCells(const QString& value) {
        if (!m_cellsJson && value == m_cells) return;
        m_source = value;
        parse(m_source, false);
    }
    void setMetrics(const QVariantMap& value) {
        if (value == m_metrics) return;
        m_metrics = value;
        emit metricsChanged();
        update();
    }
    void setCellOpacity(qreal value) {
        if (value == m_cellOpacity) return;
        m_cellOpacity = value;
        emit cellOpacityChanged();
        update();
    }

    Q_INVOKABLE bool save(const QString& path) {
        const qreal dpr = m_dpr > 0 ? m_dpr : (window() ? window()->effectiveDevicePixelRatio() : 1);
        const QImage image = render(dpr);
        return !image.isNull() && image.save(path);
    }

signals:
    void skewChanged();
    void cellsChanged();
    void metricsChanged();
    void cellOpacityChanged();
    void painted(double ms);

protected:
    QSGNode* updatePaintNode(QSGNode* old, UpdatePaintNodeData*) override {
        QElapsedTimer timer;
        timer.start();
        const qreal dpr = window()->effectiveDevicePixelRatio();
        QSGNode* node = QSGRendererInterface::isApiRhiBased(window()->rendererInterface()->graphicsApi())
            ? updateCellNode(static_cast<CellNode*>(old), dpr)
            : updateImageNode(static_cast<QSGImageNode*>(old), dpr);
        // What a frame costs this item: taking it in and laying it out.
        const double total = timer.nsecsElapsed() / 1e6 + m_lineMs;
        QMetaObject::invokeMethod(this, [this, total] { emit painted(total); }, Qt::QueuedConnection);
        return node;
    }

private:
    // "x,y,char,#rrggbb" records split by ';'. Read by hand: a tokenizer and
    // toInt per field cost about a microsecond a cell, at 30 frames of 15,000.
    // With json, a character field may be one escape; anything else escaped
    // returns false with nothing parsed.
    bool parse(QStringView cells, bool json) {
        m_parsed.clear();
        m_cells = cells;
        m_cellsJson = json;
        m_cellsRuns = false;
        QStringView lastColor;
        QRgb color = 0;
        const QChar* at = cells.data();
        const QChar* const end = at + cells.size();
        while (true) {
            const QChar* const recordEnd = std::find(at, end, QChar(u';'));
            QStringView fields[4];
            int count = 0;
            for (const QChar* field = at; count < 4;) {
                const QChar* const fieldEnd = std::find(field, recordEnd, QChar(u','));
                fields[count++] = QStringView(field, fieldEnd);
                if (fieldEnd == recordEnd) break;
                field = fieldEnd + 1;
            }
            if (count == 4) {
                if (json) {
                    for (QStringView& field : fields)
                        if (field.contains(u'\\') && !unescapeCharacter(field)) {
                            m_parsed.clear();
                            m_cells = QStringView();
                            m_cellsJson = false;
                            return false;
                        }
                }
                const QStringView ch = fields[2], style = fields[3];
                if (style != lastColor) {
                    color = parseColor(style);
                    lastColor = style;
                }
                m_parsed.push_back({toInt(fields[0]), toInt(fields[1]), ch, color, kindOf(ch), codeOf(ch)});
            }
            if (recordEnd == end) break;
            at = recordEnd + 1;
        }
        emit cellsChanged();
        update();
        return true;
    }

    // "x,y,#rrggbb,count,characters" records split by ';': count characters
    // for the cells from x onwards on row y. Returns false with nothing parsed
    // when the text is not that.
    bool parseRuns(QStringView runs, bool json) {
        m_parsed.clear();
        m_cells = runs;
        m_cellsJson = json;
        m_cellsRuns = true;
        auto fail = [this] {
            m_parsed.clear();
            m_cells = QStringView();
            m_cellsJson = m_cellsRuns = false;
            return false;
        };
        const QChar* at = runs.data();
        const QChar* const end = at + runs.size();
        auto field = [&](QStringView& out) {
            const QChar* const comma = std::find(at, end, QChar(u','));
            if (comma == end) return false;
            out = QStringView(at, comma);
            at = comma + 1;
            return true;
        };
        while (at < end) {
            QStringView x, y, style, count;
            if (!field(x) || !field(y) || !field(style) || !field(count)) return fail();
            const int column = toInt(x), row = toInt(y), length = toInt(count);
            const QRgb color = parseColor(style);
            // A long run gets room for all its characters at once (never more
            // than the text left), trimmed to what was read; short ones append.
            const qsizetype first = m_parsed.size();
            const qsizetype room = length >= 4 ? qMax(0, qMin<qsizetype>(length, end - at)) : 0;
            m_parsed.resizeForOverwrite(first + room);
            Cell* cell = m_parsed.data() + first;
            for (int i = 0; i < length; ++i) {
                if (at >= end) return fail();
                qsizetype size = 1;
                QStringView ch;
                char32_t code;
                if (json && *at == u'\\') {
                    size = at + 1 < end && at[1] == u'u' ? 6 : 2;
                    if (end - at < size) return fail();
                    ch = QStringView(at, size);
                    if (!unescapeCharacter(ch)) return fail();
                    code = ch[0].unicode();
                } else if (at->isHighSurrogate() && at + 1 < end && at[1].isLowSurrogate()) {
                    size = 2;
                    ch = QStringView(at, 2);
                    code = QChar::surrogateToUcs4(at[0], at[1]);
                } else {
                    ch = QStringView(at, 1);
                    code = at->unicode();
                }
                const Cell parsed{column + i, row, ch, color, ch.size() == 1 ? kindOfCode(code) : Glyph, code};
                if (room) *cell++ = parsed;
                else m_parsed.push_back(parsed);
                at += size;
            }
            if (room) m_parsed.resize(cell - m_parsed.data());
            if (at < end && *at++ != u';') return fail();
        }
        emit cellsChanged();
        update();
        return true;
    }

    static char32_t codeOf(QStringView ch) {
        if (ch.size() == 1) return ch[0].unicode();
        if (ch.size() == 2 && ch[0].isHighSurrogate() && ch[1].isLowSurrogate()) return QChar::surrogateToUcs4(ch[0], ch[1]);
        return 0;
    }

    static Kind kindOfCode(char32_t code) {
        switch (code) {
        case 0x20: return Blank; // a space draws nothing: its glyph has no pixels
        case 0x2588: return Block;
        case 0x25ac: return Bar;
        case 0x258c: return HalfBlock;
        case 0x25aa: return Dot;
        default: return Glyph;
        }
    }

    static Kind kindOf(QStringView ch) {
        if (ch.size() != 1) return Glyph;
        switch (ch[0].unicode()) {
        case 0x20: return Blank; // a space draws nothing: its glyph has no pixels
        case 0x2588: return Block;
        case 0x25ac: return Bar;
        case 0x258c: return HalfBlock;
        case 0x25aa: return Dot;
        default: return Glyph;
        }
    }

    // A field that is exactly one JSON escape, pointed at the character it means.
    static bool unescapeCharacter(QStringView& field) {
        // Control characters, then '"' and '\\': every character the daemon escapes.
        static const QString escaped = [] {
            QString text;
            for (char16_t c = 0; c < 0x20; ++c) text.append(QChar(c));
            return text + u'"' + u'\\';
        }();
        if (field == u"\\\"") { field = QStringView(escaped).sliced(0x20, 1); return true; }
        if (field == u"\\\\") { field = QStringView(escaped).sliced(0x21, 1); return true; }
        if (field.size() == 6 && field.startsWith(u"\\u")) {
            bool ok = false;
            const uint code = field.sliced(2).toUInt(&ok, 16);
            if (ok && code < 0x20) { field = QStringView(escaped).sliced(code, 1); return true; }
        }
        return false;
    }

    static QString unescape(QStringView raw) {
        QString cells;
        cells.reserve(raw.size());
        for (qsizetype i = 0; i < raw.size(); ++i) {
            const QChar c = raw[i];
            if (c != u'\\' || i + 1 >= raw.size()) { cells.append(c); continue; }
            const QChar next = raw[++i];
            if (next == u'u' && i + 4 < raw.size()) {
                cells.append(QChar(raw.sliced(i + 1, 4).toUShort(nullptr, 16)));
                i += 4;
            } else {
                cells.append(next);
            }
        }
        return cells;
    }

    // Plain decimal digits by hand; anything else gets QStringView's reading.
    static int toInt(QStringView text) {
        qsizetype i = 0;
        const bool negative = !text.isEmpty() && text[0] == u'-';
        if (negative || (!text.isEmpty() && text[0] == u'+')) i = 1;
        if (i == text.size()) return text.toInt();
        qint64 value = 0;
        for (; i < text.size(); ++i) {
            const char16_t c = text[i].unicode();
            if (c < u'0' || c > u'9' || value > INT_MAX) return text.toInt();
            value = value * 10 + (c - u'0');
        }
        if (value > INT_MAX) return text.toInt();
        return int(negative ? -value : value);
    }

    QSize deviceSize(qreal dpr) const { return (size() * dpr).toSize(); }

    void prepareFont(qreal dpr) {
        const int fontPixel = int(m_metrics.value("font", 11).toDouble());
        if (fontPixel == m_fontPixel && dpr == m_dpr) return;
        QFont mono;
        mono.setStyleHint(QFont::Monospace);
        m_font = QFont();
        m_font.setFamily(mono.defaultFamily());
        m_font.setBold(true);
        m_font.setPixelSize(fontPixel);
        m_fontPixel = fontPixel;
        m_dpr = dpr;
        m_coverage.clear();
        m_coverageBytes = 0;
        forgetGlyphSlots();
        resetAtlas();
    }

    // Calls draw(cell, target, glyph, source) for every cell in order, with the
    // device pixels it covers; glyph is null for solid cells. Both the GPU and
    // the image path go through here, so they cover the same pixels.
    template <class Draw>
    void place(qreal dpr, Draw&& draw) {
        prepareFont(dpr);
        const qreal cw = m_metrics.value("cw", 1).toDouble();
        const qreal ch = m_metrics.value("ch", 1).toDouble();
        const qreal x0 = m_metrics.value("x", 0).toDouble();
        const qreal y0 = m_metrics.value("y", 0).toDouble();
        const QRect area(QPoint(0, 0), deviceSize(dpr));
        // A cell's pixels depend only on its column and row: work those out
        // once a frame instead of once a cell.
        auto span = [dpr](qreal from, qreal size) { return Span{qRound(from * dpr), qRound(from * dpr + size * dpr)}; };
        auto column = [&](int c) {
            const qreal x = x0 + c * cw, bx = std::floor(x);
            return Line{bx, x - bx, qRound((x - bx) * 64), span(x, cw), span(x, cw * 0.5), span(x + 0.3 * cw, cw * 0.4)};
        };
        auto row = [&](int r) {
            const qreal y = y0 + r * ch, baseline = y + ch * 0.82, by = std::floor(baseline);
            return Line{by, baseline - by, qRound((baseline - by) * 64), span(y, ch), span(y + 0.36 * ch, 0.28 * ch), span(y + 0.38 * ch, ch * 0.24)};
        };
        int columns = 0, rows = 0;
        bool tabled = true;
        for (const auto& cell : std::as_const(m_parsed)) {
            tabled = tabled && cell.x >= 0 && cell.y >= 0 && cell.x < 4096 && cell.y < 4096;
            columns = qMax(columns, cell.x + 1);
            rows = qMax(rows, cell.y + 1);
        }
        if (tabled) {
            m_columns.resize(columns);
            m_rows.resize(rows);
            for (int c = 0; c < columns; ++c) m_columns[c] = column(c);
            for (int r = 0; r < rows; ++r) m_rows[r] = row(r);
        }
        for (const auto& cell : std::as_const(m_parsed)) {
            if (cell.kind == Blank) continue;
            const Line across = tabled ? m_columns[cell.x] : column(cell.x);
            const Line down = tabled ? m_rows[cell.y] : row(cell.y);
            if (cell.kind != Glyph) {
                Span h = across.full, v = down.full;
                if (cell.kind == Bar) v = down.part;
                else if (cell.kind == HalfBlock) h = across.part;
                else if (cell.kind == Dot) { h = across.dot; v = down.dot; }
                const QRect target = QRect(QPoint(h.from, v.from), QPoint(h.to - 1, v.to - 1)).intersected(area);
                if (!target.isEmpty()) draw(cell, target, static_cast<Coverage*>(nullptr), QPoint());
                continue;
            }
            Coverage* glyph = glyphAt(cell, dpr, across, down);
            if (!glyph || glyph->mask.isNull()) continue;
            const QPointF origin = QPointF(across.start + glyph->bounds.x(), down.start + glyph->bounds.y()) * dpr;
            const QRect full(QPoint(qRound(origin.x()) + glyph->offset.x(), qRound(origin.y()) + glyph->offset.y()), glyph->mask.size());
            const QRect target = full.intersected(area);
            if (!target.isEmpty()) draw(cell, target, glyph, target.topLeft() - full.topLeft());
        }
    }

    // Most cells hit the same few glyphs: a direct-mapped table in front of the
    // hash. It holds pointers into the hash, so any change to it empties the table.
    struct GlyphSlot { quint64 key = ~0ull; Coverage* glyph = nullptr; };
    std::array<GlyphSlot, 1024> m_glyphSlots;
    void forgetGlyphSlots() { m_glyphSlots.fill(GlyphSlot()); }

    Coverage* glyphAt(const Cell& cell, qreal dpr, const Line& across, const Line& down) {
        if (!cell.code) return nullptr;
        const quint64 key = quint64(cell.code) << 16 | quint64(across.sub) << 8 | quint64(down.sub);
        GlyphSlot& slot = m_glyphSlots[(key * 0x9E3779B97F4A7C15ull) >> 54];
        if (slot.key == key) return slot.glyph;
        Coverage* glyph = glyphCoverage(cell.ch, dpr, across.fraction, down.fraction);
        // glyphCoverage may have emptied the table; this slot is still the one to fill.
        slot = GlyphSlot{key, glyph};
        return glyph;
    }

    // The glyph as one byte per device pixel, set where it is drawn.
    Coverage* glyphCoverage(QStringView ch, qreal dpr, qreal fx, qreal fy) {
        const int sx = qRound(fx * 64), sy = qRound(fy * 64);
        char32_t code = 0;
        if (ch.size() == 1) code = ch[0].unicode();
        else if (ch.size() == 2 && ch[0].isHighSurrogate() && ch[1].isLowSurrogate()) code = QChar::surrogateToUcs4(ch[0], ch[1]);
        else return nullptr;
        const quint64 key = quint64(code) << 16 | quint64(sx) << 8 | quint64(sy);
        if (auto found = m_coverage.find(key); found != m_coverage.end()) return &found.value();
        if (m_coverageBytes > MaxMaskBytes) {
            m_coverage.clear();
            m_coverageBytes = 0;
            resetAtlas();
        }
        forgetGlyphSlots();
        QPainterPath path;
        path.addText(fx, fy, m_font, ch.toString());
        path.setFillRule(Qt::WindingFill);
        Coverage entry;
        entry.bounds = path.boundingRect().adjusted(-1, -1, 1, 1).toAlignedRect();
        if (!entry.bounds.isEmpty()) {
            QImage image(QSize(qCeil(entry.bounds.width() * dpr), qCeil(entry.bounds.height() * dpr)), QImage::Format_ARGB32_Premultiplied);
            image.setDevicePixelRatio(dpr);
            image.fill(Qt::transparent);
            {
                QPainter raster(&image);
                raster.setRenderHint(QPainter::Antialiasing, false);
                raster.translate(-entry.bounds.topLeft());
                raster.fillPath(path, Qt::white);
            }
            const QImage mask = image.convertToFormat(QImage::Format_Alpha8);
            // Only the set pixels: the rest would cost blits and atlas room.
            int top = mask.height(), bottom = -1, left = mask.width(), right = -1;
            for (int row = 0; row < mask.height(); ++row) {
                const uchar* line = mask.constScanLine(row);
                for (int col = 0; col < mask.width(); ++col)
                    if (line[col]) {
                        top = qMin(top, row); bottom = row;
                        left = qMin(left, col); right = qMax(right, col);
                    }
            }
            if (bottom >= 0) {
                entry.offset = QPoint(left, top);
                entry.mask = mask.copy(left, top, right - left + 1, bottom - top + 1);
            }
            m_coverageBytes += entry.mask.sizeInBytes();
        }
        return &m_coverage.insert(key, entry).value();
    }

    void resetAtlas() {
        m_atlas = QImage(AtlasWidth, 256, QImage::Format_RGBA8888_Premultiplied);
        m_atlas.fill(Qt::transparent);
        for (int row = 0; row < 4; ++row)
            std::fill_n(reinterpret_cast<quint32*>(m_atlas.scanLine(row)), 4, 0xffffffffu);
        m_shelf = QPoint(5, 0);
        m_shelfHeight = 5;
        for (auto& glyph : m_coverage) glyph.atlas = QPoint(-1, -1);
        ++m_atlasVersion;
    }

    // Copies a glyph into the atlas the first time the GPU draws it.
    bool pack(Coverage* glyph) {
        if (glyph->atlas.x() >= 0) return true;
        const QSize size = glyph->mask.size() + QSize(1, 1);
        if (size.width() > AtlasWidth) return false;
        if (m_shelf.x() + size.width() > AtlasWidth) m_shelf = QPoint(0, m_shelf.y() + std::exchange(m_shelfHeight, 0));
        if (m_shelf.y() + size.height() > m_atlas.height()) {
            if (m_atlas.height() * 2 > MaxAtlasHeight) return false;
            QImage taller(AtlasWidth, m_atlas.height() * 2, m_atlas.format());
            taller.fill(Qt::transparent);
            std::memcpy(taller.bits(), m_atlas.constBits(), m_atlas.sizeInBytes());
            m_atlas = taller;
        }
        glyph->atlas = m_shelf;
        for (int row = 0; row < glyph->mask.height(); ++row) {
            const uchar* mask = glyph->mask.constScanLine(row);
            auto line = reinterpret_cast<quint32*>(m_atlas.scanLine(m_shelf.y() + row)) + m_shelf.x();
            for (int col = 0; col < glyph->mask.width(); ++col)
                line[col] = mask[col] ? 0xffffffffu : 0u;
        }
        m_shelf.rx() += size.width();
        m_shelfHeight = qMax(m_shelfHeight, size.height());
        ++m_atlasVersion;
        return true;
    }

    // Vertices for the background and every cell, in drawing order.
    bool buildVertices(qreal dpr) {
        // Texture coordinates go out normalized; if packing grows the atlas,
        // the frame is laid out again against its final size.
        const int atlasHeight = m_atlas.height();
        m_vertices.resizeForOverwrite((m_parsed.size() + 1) * 4);
        CellVertex* next = m_vertices.data();
        const float scale = float(1 / dpr);
        const float u = 1.0f / m_atlas.width(), v = 1.0f / atlasHeight;
        const QSize device = deviceSize(dpr);
        const int alpha = qRound(qBound(0.0, m_cellOpacity, 1.0) * 255);
        bool packed = true;
        auto quad = [&](const QRect& target, float u0, float v0, float u1, float v1, QRgb color, int a) {
            uchar r = uchar(qRed(color)), g = uchar(qGreen(color)), b = uchar(qBlue(color));
            if (a != 255) {
                r = uchar((r * a + 127) / 255);
                g = uchar((g * a + 127) / 255);
                b = uchar((b * a + 127) / 255);
            }
            const float left = target.left() * scale, top = target.top() * scale;
            const float right = (target.right() + 1) * scale, bottom = (target.bottom() + 1) * scale;
            *next++ = {left, top, u0, v0, r, g, b, uchar(a)};
            *next++ = {right, top, u1, v0, r, g, b, uchar(a)};
            *next++ = {left, bottom, u0, v1, r, g, b, uchar(a)};
            *next++ = {right, bottom, u1, v1, r, g, b, uchar(a)};
        };
        const float solidU = 2.5f * u, solidV = 2.5f * v;
        quad(QRect(QPoint(0, 0), device), solidU, solidV, solidU, solidV, Background, 255);
        place(dpr, [&](const Cell& cell, const QRect& target, Coverage* glyph, QPoint source) {
            if (!glyph) {
                quad(target, solidU, solidV, solidU, solidV, cell.color, alpha);
                return;
            }
            if (!pack(glyph)) { packed = false; return; }
            const int x = glyph->atlas.x() + source.x(), y = glyph->atlas.y() + source.y();
            quad(target, float(x) * u, float(y) * v, float(x + target.width()) * u, float(y + target.height()) * v, cell.color, alpha);
        });
        m_vertices.resize(next - m_vertices.data());
        if (packed && m_atlas.height() != atlasHeight) return buildVertices(dpr);
        return packed;
    }

    QSGNode* updateCellNode(CellNode* node, qreal dpr) {
        if (!node) node = new CellNode;
        if (!buildVertices(dpr)) {
            // The atlas filled up: start it over with only this frame's glyphs.
            resetAtlas();
            buildVertices(dpr);
        }
        if (node->atlasVersion != m_atlasVersion) {
            // Made before the old one goes: at the same address the renderer
            // would take it for the texture it already bound.
            QSGTexture* old = std::exchange(node->atlas, window()->createTextureFromImage(m_atlas));
            delete old;
            node->atlas->setFiltering(QSGTexture::Nearest);
            node->atlasVersion = m_atlasVersion;
            CellNode::setTexture(node->cells, node->atlas);
        }
        fill(node->cells->geometry(), m_vertices);
        node->cells->markDirty(QSGNode::DirtyGeometry);

        const QImage mask = skewMask(dpr);
        if (mask.isNull()) {
            if (node->mask->parent()) node->removeChildNode(node->mask);
        } else {
            if (node->maskTexture == nullptr || node->maskImage.cacheKey() != mask.cacheKey()) {
                QSGTexture* old = std::exchange(node->maskTexture, window()->createTextureFromImage(mask));
                delete old;
                node->maskTexture->setFiltering(QSGTexture::Nearest);
                node->maskImage = mask;
                CellNode::setTexture(node->mask, node->maskTexture);
            }
            const float w = float(mask.width() / dpr), h = float(mask.height() / dpr);
            const QVector<CellVertex> quad = {{0, 0, 0, 0, 255, 255, 255, 255}, {w, 0, 1, 0, 255, 255, 255, 255},
                                              {0, h, 0, 1, 255, 255, 255, 255}, {w, h, 1, 1, 255, 255, 255, 255}};
            fill(node->mask->geometry(), quad, 1);
            node->mask->markDirty(QSGNode::DirtyGeometry);
            if (!node->mask->parent()) node->appendChildNode(node->mask);
        }
        return node;
    }

    // The quad count changes every frame. Geometry grows in blocks with the
    // spare quads collapsed to a point, which draws nothing, so the index list
    // is only written when the block count changes.
    static void fill(QSGGeometry* geometry, const QVector<CellVertex>& vertices, int block = 512) {
        const int quads = int(vertices.size() / 4);
        const int capacity = (quads + block - 1) / block * block;
        if (geometry->vertexCount() != capacity * 4 || geometry->indexCount() != capacity * 6) {
            geometry->allocate(capacity * 4, capacity * 6);
            auto index = geometry->indexDataAsUInt();
            for (int q = 0; q < capacity; ++q) {
                const quint32 first = quint32(q * 4);
                *index++ = first; *index++ = first + 1; *index++ = first + 2;
                *index++ = first + 1; *index++ = first + 3; *index++ = first + 2;
            }
        }
        auto data = static_cast<CellVertex*>(geometry->vertexData());
        std::memcpy(data, vertices.constData(), vertices.size() * sizeof(CellVertex));
        std::memset(static_cast<void*>(data + quads * 4), 0, (capacity - quads) * 4 * sizeof(CellVertex));
    }

    // Transparent outside the slice's skewed edges; null when it has none.
    QImage skewMask(qreal dpr) {
        if (m_skew == 0) return QImage();
        const QSize physical(qCeil(width() * dpr), qCeil(height() * dpr));
        if (m_mask.size() == physical && m_mask.devicePixelRatio() == dpr && m_maskSkew == m_skew)
            return m_mask;
        QImage mask(physical, QImage::Format_ARGB32_Premultiplied);
        mask.setDevicePixelRatio(dpr);
        mask.fill(Qt::transparent);
        QPainter painter(&mask);
        painter.setRenderHint(QPainter::Antialiasing, true);
        painter.setPen(Qt::NoPen);
        painter.setBrush(Qt::white);
        const qreal k = qMin(std::abs(m_skew), width());
        const qreal left = m_skew > 0 ? k : 0;
        painter.drawPolygon(QPolygonF{
            QPointF(left, 0), QPointF(width()-k+left, 0),
            QPointF(width()-left, height()), QPointF(k-left, height())
        });
        painter.end();
        m_maskSkew = m_skew;
        m_mask = mask;
        return m_mask;
    }

    // The frame as an image, for save() and a scene graph without a GPU.
    QImage render(qreal dpr) {
        QImage image(deviceSize(dpr), QImage::Format_ARGB32_Premultiplied);
        if (image.isNull()) return image;
        image.fill(QColor::fromRgb(Background));
        const int alpha = qRound(qBound(0.0, m_cellOpacity, 1.0) * 255);
        auto blend = [alpha](quint32& pixel, QRgb color) {
            if (alpha == 255) { pixel = color | 0xff000000; return; }
            auto mix = [alpha](int src, int dst) { return (src * alpha + dst * (255 - alpha) + 127) / 255; };
            pixel = qRgba(mix(qRed(color), qRed(pixel)), mix(qGreen(color), qGreen(pixel)), mix(qBlue(color), qBlue(pixel)),
                          mix(255, qAlpha(pixel)));
        };
        place(dpr, [&](const Cell& cell, const QRect& target, Coverage* glyph, QPoint source) {
            for (int row = 0; row < target.height(); ++row) {
                auto line = reinterpret_cast<quint32*>(image.scanLine(target.top() + row)) + target.left();
                const uchar* mask = glyph ? glyph->mask.constScanLine(source.y() + row) + source.x() : nullptr;
                for (int col = 0; col < target.width(); ++col)
                    if (!mask || mask[col]) blend(line[col], cell.color);
            }
        });
        const QImage mask = skewMask(dpr);
        image.setDevicePixelRatio(dpr);
        if (!mask.isNull()) {
            QPainter painter(&image);
            painter.setCompositionMode(QPainter::CompositionMode_DestinationIn);
            painter.drawImage(QPointF(0, 0), mask);
        }
        return image;
    }

    QSGNode* updateImageNode(QSGImageNode* node, qreal dpr) {
        if (!node) {
            node = window()->createImageNode();
            node->setOwnsTexture(true);
            node->setFiltering(QSGTexture::Nearest);
        }
        node->setTexture(window()->createTextureFromImage(render(dpr)));
        node->setRect(boundingRect());
        return node;
    }
};


// Runs the preview daemon and reads its output here, so a frame for the view
// on screen goes straight to it: through a QML process, a line parser and a
// JavaScript handler, each frame cost more than drawing it. Every other line
// is handed to QML as it was before.
class PreviewStream : public QObject {
    Q_OBJECT
    Q_PROPERTY(QStringList command READ command WRITE setCommand NOTIFY commandChanged)
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(int processId READ processId NOTIFY processIdChanged)
    Q_PROPERTY(QObject* sink READ sink WRITE setSink NOTIFY sinkChanged)
    Q_PROPERTY(QString sinkEffect READ sinkEffect WRITE setSinkEffect NOTIFY sinkEffectChanged)

public:
    explicit PreviewStream(QObject* parent = nullptr) : QObject(parent) {
        m_process.setProcessChannelMode(QProcess::ForwardedErrorChannel);
        connect(&m_process, &QProcess::readyReadStandardOutput, this, &PreviewStream::readLines);
        connect(&m_process, &QProcess::started, this, [this] { emit processIdChanged(); });
        connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart && m_running) { m_running = false; emit runningChanged(); }
        });
        connect(&m_process, &QProcess::finished, this, [this] {
            m_buffer.clear();
            emit processIdChanged();
            if (m_running) { m_running = false; emit runningChanged(); }
        });
    }
    ~PreviewStream() override {
        if (m_process.state() == QProcess::NotRunning) return;
        m_process.terminate();
        if (!m_process.waitForFinished(500)) m_process.kill();
    }

    QStringList command() const { return m_command; }
    void setCommand(const QStringList& value) {
        if (value == m_command) return;
        m_command = value;
        emit commandChanged();
    }
    bool running() const { return m_running; }
    void setRunning(bool value) {
        if (value == m_running) return;
        if (value) {
            // Still ending from a stop a moment ago: let it go first, so its
            // end is not taken for the new process's.
            if (m_process.state() != QProcess::NotRunning && !m_process.waitForFinished(1000)) {
                m_process.kill();
                m_process.waitForFinished(500);
            }
            m_running = true;
            if (!m_command.isEmpty()) m_process.start(m_command.first(), m_command.mid(1));
        } else {
            m_running = false;
            // The daemon's wrapper owns its process group: give it the chance to end it.
            if (m_process.state() != QProcess::NotRunning) m_process.terminate();
        }
        emit runningChanged();
    }
    int processId() const { return m_process.state() == QProcess::NotRunning ? 0 : int(m_process.processId()); }
    QObject* sink() const { return m_sink; }
    void setSink(QObject* value) {
        if (value == m_sink) return;
        m_sink = qobject_cast<CellPreview*>(value);
        emit sinkChanged();
    }
    QString sinkEffect() const { return m_sinkEffect; }
    void setSinkEffect(const QString& value) {
        if (value == m_sinkEffect) return;
        m_sinkEffect = value;
        m_runsPrefix = ("{\"fx\":\"" + value + "\",\"runs\":\"").toUtf8();
        m_cellsPrefix = ("{\"fx\":\"" + value + "\",\"cells\":\"").toUtf8();
        emit sinkEffectChanged();
    }

    Q_INVOKABLE void write(const QString& text) {
        if (m_process.state() == QProcess::Running) m_process.write(text.toUtf8());
    }

signals:
    void commandChanged();
    void runningChanged();
    void processIdChanged();
    void sinkChanged();
    void sinkEffectChanged();
    // A line that was not a frame for the sink, as the daemon wrote it.
    void line(const QString& text);
    // The sink took a frame; volume is the one the line carried.
    void frame(double volume);

private:
    void readLines() {
        m_buffer += m_process.readAllStandardOutput();
        qsizetype from = 0;
        for (qsizetype newline; (newline = m_buffer.indexOf('\n', from)) >= 0; from = newline + 1) {
            const QByteArrayView text(m_buffer.constData() + from, newline - from);
            if (m_sink && !m_sinkEffect.isEmpty() && (text.startsWith(m_runsPrefix) || text.startsWith(m_cellsPrefix))) {
                m_sink->setFrameLine(QString::fromUtf8(text));
                const qsizetype at = text.lastIndexOf(QByteArrayView("\"volume\":"));
                double volume = 0;
                if (at > 0) volume = leadingNumber(text.sliced(at + 9));
                emit frame(volume);
            } else {
                emit line(QString::fromUtf8(text));
            }
        }
        m_buffer.remove(0, from);
    }

    // What JavaScript's parseFloat(text) || 0 gives for the start of text.
    static double leadingNumber(QByteArrayView text) {
        qsizetype end = 0;
        while (end < text.size() && (std::isdigit(uchar(text[end])) || std::strchr("+-.eE", text[end]))) ++end;
        while (end > 0) {
            bool ok = false;
            const double value = QByteArray(text.first(end)).toDouble(&ok);
            if (ok) return std::isfinite(value) ? value : 0;
            --end;
        }
        return 0;
    }

    QProcess m_process;
    QStringList m_command;
    bool m_running = false;
    QByteArray m_buffer;
    QPointer<CellPreview> m_sink;
    QString m_sinkEffect;
    QByteArray m_runsPrefix, m_cellsPrefix;
};

class AmbientCellsPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char* uri) override {
        qmlRegisterType<CellPreview>(uri, 1, 0, "CellPreview");
        qmlRegisterType<PreviewStream>(uri, 1, 0, "PreviewStream");
    }
};
#include "cellpreview.moc"
