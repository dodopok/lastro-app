import LastroKit
import SwiftUI

struct HojeView: View {
    @Environment(AppStore.self) private var store
    let perform: (HomeAction) -> Void

    var body: some View {
        let model = HomeModel(ledger: store.ledger, selected: store.selectedMonth, today: store.today)
        ScrollView {
            VStack(spacing: 14) {
                header(model)
                MonthRail(months: model.rail, selected: store.selectedMonth, current: store.today.month) { m in
                    withAnimation(.smooth(duration: 0.22)) {
                        store.selectedMonth = m
                        store.heroIndex = 0
                    }
                }
                HeroCard(model: model, index: store.heroIndex) {
                    withAnimation(.smooth(duration: 0.22)) { store.heroIndex = (store.heroIndex + 1) % 3 }
                }
                shortcuts(model)
                if model.mode == .current { pendingSection(model) }
                if model.mode != .closed { pilotRow(model) }
                if let miud = model.miudezas { MiudezasCard(model: miud) { perform(.spending(.variaveis)) } }
                categories(model)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .sensoryFeedback(.selection, trigger: store.heroIndex)
        .sensoryFeedback(.selection, trigger: store.selectedMonth)
    }

    // MARK: cabeçalho

    private func header(_ model: HomeModel) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.subtitle).textStyle(13, .medium).foregroundStyle(.inkTertiary)
                Text(model.month.name).largeTitle().foregroundStyle(.ink)
                    .contentTransition(.opacity)
            }
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { perform(.history) } label: {
                        Text(String(model.month.year)).textStyle(14, .semibold).foregroundStyle(.ink)
                            .glassPill()
                    }
                    Button { perform(.push(.recibos)) } label: {
                        Image(systemName: "tray")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.ink)
                            .glassCircle()
                    }
                    .accessibilityLabel("Recibos, \(model.receiptsCount) esperando")
                }
            }
            .buttonStyle(.plain)
            // O badge fica fora do GlassEffectContainer: dentro dele o vidro o recorta.
            .overlay(alignment: .topTrailing) {
                if model.receiptsCount > 0 {
                    Text("\(model.receiptsCount)")
                        .textStyle(11, .bold)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Color.negative))
                        .overlay { Capsule().strokeBorder(Color.canvas, lineWidth: 2) }
                        .fixedSize()
                        .offset(x: 3, y: -3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    // MARK: atalhos

    private func shortcuts(_ model: HomeModel) -> some View {
        HStack(spacing: 10) {
            ForEach(model.shortcuts) { s in
                Button { perform(s.action) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.label).textStyle(12.5, .medium).foregroundStyle(.inkSecondary)
                        Text(s.value).textStyle(20, .bold, tracking: -0.025).monospacedDigit().foregroundStyle(.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(s.sub).textStyle(11.5).foregroundStyle(.ink.opacity(0.42))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .panel()
                }
                .buttonStyle(PressScale())
            }
        }
    }

    // MARK: para confirmar

    private func pendingSection(_ model: HomeModel) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Para confirmar").sectionTitle()
                Text("\(model.pendingCount)").textStyle(14, .semibold).foregroundStyle(.inkQuaternary)
                Spacer()
                Button("Ver todos") { perform(.spending(.pendentes)) }
                    .textStyle(14, .medium)
                    .foregroundStyle(.accent)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if model.pending.isEmpty {
                    Text("Tudo confirmado. O mês bate com o banco.")
                        .textStyle(14).foregroundStyle(.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 22)
                }
                ForEach(Array(model.pending.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { RowDivider() }
                    PendingRowView(row: row) { store.tapPending(row.entry) }
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .move(edge: .leading))))
                }
            }
            .panel(radius: 24)
            .animation(.smooth(duration: 0.3), value: model.pending.map(\.id))
        }
        .padding(.top, 6)
    }

    // MARK: piloto

    private func pilotRow(_ model: HomeModel) -> some View {
        Button { perform(.pilot) } label: {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(LinearGradient.accentFab, in: .rect(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Piloto automático").textStyle(15, .semibold).foregroundStyle(.ink)
                    Text(model.pilotLine).textStyle(12.5).foregroundStyle(.inkTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Chevron()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .panel()
        }
        .buttonStyle(PressScale())
    }

    // MARK: categorias

    private func categories(_ model: HomeModel) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Categorias").sectionTitle()
                Spacer()
                Text(model.categoriesRight).textStyle(12.5).monospacedDigit().foregroundStyle(.ink.opacity(0.45))
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(model.categoryCards) { card in
                    let action = model.action(for: card)
                    Button { if let action { perform(action) } } label: {
                        CategoryCardView(card: card)
                    }
                    .buttonStyle(PressScale())
                    .disabled(action == nil)
                }
            }
        }
    }
}

// MARK: - Peças

struct MonthRail: View {
    let months: [HomeModel.RailMonth]
    let selected: YearMonth
    let current: YearMonth
    let select: (YearMonth) -> Void
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(months) { m in
                let isSelected = m.month == selected
                Button { select(m.month) } label: {
                    Text(m.month.shortName)
                        .textStyle(12.5, .semibold, tracking: 0.06)
                        .foregroundStyle(isSelected ? Color.white : m.mode == .plan ? Color.ink.opacity(0.4) : Color.ink.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if isSelected {
                                Capsule().fill(.ink).matchedGeometryEffect(id: "rail", in: ns)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if m.month == current {
                                Circle().fill(isSelected ? Color.white : Color.accent).frame(width: 4, height: 4).padding(.bottom, 4)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}

struct HeroCard: View {
    let model: HomeModel
    let index: Int
    let tap: () -> Void

    var body: some View {
        let hero = model.heroes[index % model.heroes.count]
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(hero.label).textStyle(14, .semibold).foregroundStyle(.ink.opacity(0.6))
                        .contentTransition(.opacity)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule()
                                .fill(i == index % 3 ? Color.ink : Color.ink.opacity(0.2))
                                .frame(width: i == index % 3 ? 18 : 6, height: 6)
                        }
                    }
                }
                HeroAmount(value: hero.value).padding(.top, 8)
                Text(hero.sub).textStyle(13.5).foregroundStyle(.inkSecondary).padding(.top, 6)
                    .contentTransition(.opacity)

                SegmentBar(segments: model.segments).padding(.top, 20)
                FlowLegend(segments: model.segments).padding(.top, 10)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hero()
            .background(alignment: .topTrailing) {
                // Brilhos coloridos atrás do vidro
                Circle().fill(Color(OKLCH(0.72, 0.16, 262))).frame(width: 210, height: 210)
                    .blur(radius: 46).opacity(0.38).offset(x: 20, y: -30).allowsHitTesting(false)
            }
            .background(alignment: .bottomLeading) {
                Ellipse().fill(Color(OKLCH(0.85, 0.12, 160))).frame(width: 160, height: 120)
                    .blur(radius: 40).opacity(0.5).offset(x: 10, y: 30).allowsHitTesting(false)
            }
        }
        .buttonStyle(PressScale(scale: 0.99))
        .accessibilityHint("Toque para ver a próxima métrica")
    }
}

struct SegmentBar: View {
    let segments: [HomeModel.Segment]

    var body: some View {
        GeometryReader { geo in
            let total = max(1, segments.reduce(0) { $0 + max(0, $1.weight.cents) })
            let gaps = CGFloat(max(0, segments.count - 1)) * 3
            HStack(spacing: 3) {
                ForEach(segments) { s in
                    Capsule().fill(s.color)
                        .frame(width: max(6, (geo.size.width - gaps) * CGFloat(max(0, s.weight.cents)) / CGFloat(total)))
                }
            }
        }
        .frame(height: 10)
        .animation(.smooth(duration: 0.3), value: segments)
    }
}

struct FlowLegend: View {
    let segments: [HomeModel.Segment]

    var body: some View {
        FlowLayout(spacing: 14, lineSpacing: 6) {
            ForEach(segments) { s in
                HStack(spacing: 6) {
                    Circle().fill(s.color).frame(width: 7, height: 7)
                    Text(s.label).foregroundStyle(.inkSecondary)
                    Text(s.text).fontWeight(.semibold).monospacedDigit().foregroundStyle(.ink)
                }
                .textStyle(12)
                .lineLimit(1)
                .fixedSize()
            }
        }
    }
}

struct PendingRowView: View {
    let row: HomeModel.PendingRow
    let tap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: tap) {
                Circle().strokeBorder(.ink.opacity(0.22), lineWidth: 1.8)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle().inset(by: -8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.tag?.isApproval == true ? "Aprovar \(row.entry.description)" : "Confirmar \(row.entry.description)")

            if let c = row.category { CategoryIcon(c) }
            VStack(alignment: .leading, spacing: 0) {
                Text(row.entry.description).textStyle(15, .semibold).foregroundStyle(.ink).lineLimit(1)
                Text(row.meta).textStyle(12.5).foregroundStyle(.inkTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(row.value).textStyle(15, .semibold).monospacedDigit().foregroundStyle(.ink)
                if let tag = row.tag {
                    Tag(text: tag.text,
                        color: tag.isApproval ? .warning : .ink.opacity(0.45),
                        background: tag.isApproval ? Color(Palette.amber).opacity(0.14) : .ink.opacity(0.06))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct MiudezasCard: View {
    let model: HomeModel.Miudezas
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Miudezas").eyebrow().foregroundStyle(Color(OKLCH(0.52, 0.13, 62)))
                Text(model.title).textStyle(19, .bold, tracking: -0.02).foregroundStyle(.ink)
                    .multilineTextAlignment(.leading)
                FlowingDots(dots: model.dots)
                Text(model.sub).textStyle(13).foregroundStyle(.ink.opacity(0.6)).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .tinted(Color(OKLCH(0.96, 0.06, 85, alpha: 0.85)))
            .shadow(color: Color(OKLCH(0.6, 0.15, 70, alpha: 0.35)), radius: 15, y: 12)
        }
        .buttonStyle(PressScale())
    }
}

/// Bolinhas das miudezas, quebrando linha como `flex-wrap`.
struct FlowingDots: View {
    let dots: [HomeModel.Dot]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(dots) { d in
                Circle().fill(d.color).opacity(0.85).frame(width: d.size, height: d.size)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + (lineSpacing ?? spacing); line = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: maxX, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + (lineSpacing ?? spacing); line = 0 }
            line = max(line, size.height)
            s.place(at: CGPoint(x: x, y: y + 0), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
        }
    }
}

struct CategoryCardView: View {
    let card: HomeModel.CategoryCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CategoryIcon(card.category, size: 32, radius: 10)
                Spacer()
                Text(card.percentText).textStyle(11.5, .semibold).monospacedDigit().foregroundStyle(.ink.opacity(0.38))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(card.category.name).textStyle(13.5, .semibold).foregroundStyle(.ink).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(card.amount).textStyle(18, .bold, tracking: -0.025).foregroundStyle(.ink)
                    Text(card.of).textStyle(11.5).foregroundStyle(.inkQuaternary)
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            ProgressBar(fraction: card.fraction, color: card.barColor)
            Text(card.sub).textStyle(12, .medium).foregroundStyle(card.subColor).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

#Preview {
    ZStack {
        Backdrop()
        HojeView { _ in }
    }
    .environment(AppStore.preview())
}
