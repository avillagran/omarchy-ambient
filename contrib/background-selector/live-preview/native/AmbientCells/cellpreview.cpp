// Paints a preview frame from native code. The carousel loads this if it can
// and keeps its Canvas otherwise, so a shell built on another Qt only loses speed.
#include <QCache>
#include <QElapsedTimer>
#include <QHash>
#include <QImage>
#include <QMetaObject>
#include <QPainter>
#include <QPainterPath>
#include <QPolygonF>
#include <QQmlExtensionPlugin>
#include <QQuickPaintedItem>
#include <QVariantMap>
#include <QVector>
#include <QStringTokenizer>
#include <QtQml/qqml.h>
#include <cmath>

class CellPreview : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(qreal skew READ skew WRITE setSkew NOTIFY skewChanged)
    Q_PROPERTY(QString cells READ cells WRITE setCells NOTIFY cellsChanged)
    Q_PROPERTY(QVariantMap metrics READ metrics WRITE setMetrics NOTIFY metricsChanged)
    Q_PROPERTY(qreal cellOpacity READ cellOpacity WRITE setCellOpacity NOTIFY cellOpacityChanged)

    struct Cell {
        int x, y;
        QStringView ch;
        QColor color;
    };
    static constexpr int MaxPaths = 4096;
    static constexpr int MaxMaskBytes = 8 * 1024 * 1024;

    qreal m_skew = 0;
    QImage m_leftMask, m_rightMask;
    QSize m_maskSize;
    qreal m_maskDpr = 0;
    qreal m_maskSkew = 0;
    QString m_cells;
    QVariantMap m_metrics;
    qreal m_cellOpacity = 1;
    QVector<Cell> m_parsed;
    QHash<QString, QPainterPath> m_paths;
    QCache<QString, QImage> m_masks{MaxMaskBytes};
    int m_fontPixel = -1;
    qreal m_dpr = -1;

public:
    explicit CellPreview(QQuickItem* parent = nullptr) : QQuickPaintedItem(parent) {
        setAntialiasing(false);
        setMipmap(false);
        setOpaquePainting(true);
        setFillColor(QColor());
    }
    qreal skew() const { return m_skew; }
    void setSkew(qreal value) {
        if (value == m_skew) return;
        m_skew = value;
        setOpaquePainting(value == 0);
        emit skewChanged();
        update();
    }
    QString cells() const { return m_cells; }
    QVariantMap metrics() const { return m_metrics; }
    qreal cellOpacity() const { return m_cellOpacity; }

    void setCells(const QString& value) {
        if (value == m_cells) return;
        // Cell views borrow m_cells; discard them before replacing its storage.
        m_parsed.clear();
        m_cells = value;
        QStringView lastColor;
        QColor color;
        for (const auto record : QStringTokenizer{QStringView{m_cells}, u';'}) {
            auto fields = QStringTokenizer{record, u','};
            auto it = fields.begin();
            const auto end = fields.end();
            if (it == end) continue;
            const int x = (*it).toInt();
            if (++it == end) continue;
            const int y = (*it).toInt();
            if (++it == end) continue;
            const auto ch = *it;
            if (++it == end) continue;
            const auto style = *it;
            if (style != lastColor) {
                color = QColor::fromString(style);
                lastColor = style;
            }
            m_parsed.push_back({x, y, ch, color});
        }
        emit cellsChanged();
        update();
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
        const qreal dpr = m_dpr > 0 ? m_dpr : 1;
        QImage image((size() * dpr).toSize(), QImage::Format_ARGB32_Premultiplied);
        if (image.isNull()) return false;
        image.setDevicePixelRatio(dpr);
        QPainter painter(&image);
        paintFrame(&painter);
        painter.end();
        return image.save(path);
    }

    void paint(QPainter* painter) override {
        QElapsedTimer timer;
        timer.start();
        paintFrame(painter);
        const double ms = timer.nsecsElapsed() / 1e6;
        QMetaObject::invokeMethod(this, [this, ms] { emit painted(ms); }, Qt::QueuedConnection);
    }

signals:
    void skewChanged();
    void cellsChanged();
    void metricsChanged();
    void cellOpacityChanged();
    void painted(double ms);

private:
    void paintFrame(QPainter* p) {
        p->fillRect(boundingRect(), QColor("#07070d"));
        p->setRenderHint(QPainter::Antialiasing, false);
        p->setRenderHint(QPainter::TextAntialiasing, false);
        p->setRenderHint(QPainter::SmoothPixmapTransform, false);
        p->setOpacity(m_cellOpacity);

        const qreal cw = m_metrics.value("cw", 1).toDouble();
        const qreal ch = m_metrics.value("ch", 1).toDouble();
        const qreal x0 = m_metrics.value("x", 0).toDouble();
        const qreal y0 = m_metrics.value("y", 0).toDouble();
        const int fontPixel = int(m_metrics.value("font", 11).toDouble());
        const qreal dpr = std::abs(p->deviceTransform().m11());

        QFont mono;
        mono.setStyleHint(QFont::Monospace);
        QFont font;
        font.setFamily(mono.defaultFamily());
        font.setBold(true);
        font.setPixelSize(fontPixel);
        p->setFont(font);

        if (fontPixel != m_fontPixel || dpr != m_dpr || m_paths.size() > MaxPaths) {
            m_paths.clear();
            m_masks.clear();
            m_fontPixel = fontPixel;
            m_dpr = dpr;
        }

        QVector<QRectF> rects;
        rects.reserve(m_parsed.size());
        QColor brush;
        p->setPen(Qt::NoPen);
        auto flush = [&] {
            if (rects.isEmpty()) return;
            p->setBrush(brush);
            p->drawRects(rects.constData(), rects.size());
            rects.clear();
        };
        for (const auto& cell : m_parsed) {
            const qreal x = x0 + cell.x * cw, y = y0 + cell.y * ch;
            QRectF rect;
            if (cell.ch == QStringLiteral("█")) rect = QRectF(x, y, cw, ch);
            else if (cell.ch == QStringLiteral("▬")) rect = QRectF(x, y + 0.36 * ch, cw, 0.28 * ch);
            else if (cell.ch == QStringLiteral("▌")) rect = QRectF(x, y, cw * 0.5, ch);
            else if (cell.ch == QStringLiteral("▪")) rect = QRectF(x + 0.3 * cw, y + 0.38 * ch, cw * 0.4, ch * 0.24);
            else {
                flush();
                paintGlyph(p, font, dpr, cell, x, y + ch * 0.82);
                continue;
            }
            if (brush != cell.color) { flush(); brush = cell.color; }
            rects.push_back(rect);
        }
        flush();
        // Only the edge strips contain transparency. Blending the whole frame
        // here would replace the GPU saving with a large CPU cost.
        if (m_skew != 0) {
            const QSize physical(qCeil(width() * dpr), qCeil(height() * dpr));
            if (m_maskSize != physical || m_maskDpr != dpr || m_maskSkew != m_skew) {
                QImage mask(physical, QImage::Format_ARGB32_Premultiplied);
                mask.setDevicePixelRatio(dpr);
                mask.fill(Qt::transparent);
                QPainter maskPainter(&mask);
                maskPainter.setRenderHint(QPainter::Antialiasing, true);
                maskPainter.setPen(Qt::NoPen);
                maskPainter.setBrush(Qt::white);
                const qreal k = qMin(std::abs(m_skew), width());
                const qreal left = m_skew > 0 ? k : 0;
                maskPainter.drawPolygon(QPolygonF{
                    QPointF(left, 0), QPointF(width()-k+left, 0),
                    QPointF(width()-left, height()), QPointF(k-left, height())
                });
                maskPainter.end();
                const int strip = qMin(physical.width(), qCeil(k * dpr));
                if (strip * 2 <= physical.width()) {
                    m_leftMask = mask.copy(0, 0, strip, physical.height());
                    m_rightMask = mask.copy(physical.width()-strip, 0, strip, physical.height());
                } else {
                    // Wide skews have overlapping strips: apply their mask once.
                    m_leftMask = mask;
                    m_rightMask = QImage();
                }
                m_maskSize = physical;
                m_maskDpr = dpr;
                m_maskSkew = m_skew;
            }
            p->setOpacity(1);
            p->setCompositionMode(QPainter::CompositionMode_DestinationIn);
            p->drawImage(QPointF(0,0), m_leftMask);
            if (!m_rightMask.isNull())
                p->drawImage(QPointF((physical.width()-m_rightMask.width()) / dpr, 0), m_rightMask);
            p->setCompositionMode(QPainter::CompositionMode_SourceOver);
        }
    }

    void paintGlyph(QPainter* p, const QFont& font, qreal dpr, const Cell& cell, qreal x, qreal baseline) {
        const qreal bx = std::floor(x), by = std::floor(baseline);
        const qreal fx = x - bx, fy = baseline - by;
        const QString key = cell.ch.toString() + QChar(0xf000 + qRound(fx * 64)) + QChar(0xf100 + qRound(fy * 64));
        auto path = m_paths.find(key);
        if (path == m_paths.end()) {
            QPainterPath glyph;
            glyph.addText(fx, fy, font, cell.ch.toString());
            glyph.setFillRule(Qt::WindingFill);
            path = m_paths.insert(key, glyph);
        }
        const QRect bounds = path.value().boundingRect().adjusted(-1, -1, 1, 1).toAlignedRect();
        if (bounds.isEmpty()) return;

        const QString maskKey = key + QString::number(cell.color.rgba(), 16);
        QImage* mask = m_masks.object(maskKey);
        if (!mask) {
            auto image = new QImage(QSize(qCeil(bounds.width() * dpr), qCeil(bounds.height() * dpr)), QImage::Format_ARGB32_Premultiplied);
            image->setDevicePixelRatio(dpr);
            image->fill(Qt::transparent);
            {
                QPainter raster(image);
                raster.setRenderHint(QPainter::Antialiasing, false);
                raster.translate(-bounds.topLeft());
                raster.fillPath(path.value(), cell.color);
            }
            const int cost = int(image->sizeInBytes());
            if (!m_masks.insert(maskKey, image, cost)) return;
            mask = m_masks.object(maskKey);
            if (!mask) return;
        }
        p->drawImage(QPointF(bx + bounds.x(), by + bounds.y()), *mask);
    }
};

class AmbientCellsPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char* uri) override { qmlRegisterType<CellPreview>(uri, 1, 0, "CellPreview"); }
};
#include "cellpreview.moc"
