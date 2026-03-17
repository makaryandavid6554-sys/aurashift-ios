import SwiftUI

struct OnboardingView: View {
    let onFinish: (_ targetTab: Int?) -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var currentPage = 0
    @State private var visibleAuroraPoints = 0
    @State private var auroraTask: Task<Void, Never>?

    private var ctaGradient: LinearGradient {
        AccentGradients.calmIndigoBlue
    }

    private let coreFeatures: [OnboardingItem] = [
        .init(icon: "clock.badge.checkmark", title: "Смена", body: "Добавляем рабочий день за пару тапов"),
        .init(icon: "rublesign.circle", title: "Доходы", body: "Фиксируем выручку и видим динамику"),
        .init(icon: "creditcard", title: "Расходы", body: "Учитываем траты без лишних шагов"),
        .init(icon: "text.bubble", title: "Заметки и чат", body: "Сохраняем идеи и важные детали по сменам")
    ]

    private let secondaryFeatures: [OnboardingItem] = [
        .init(icon: "location", title: "Геопозиция", body: "Понимаем контекст района и рабочую активность"),
        .init(icon: "cloud.sun", title: "Погода", body: "Учитываем погодные условия для прогноза спроса"),
        .init(icon: "sparkles", title: "Рекомендации", body: "Персональные подсказки по времени и нагрузке"),
        .init(icon: "target", title: "Цели и статистика", body: "Контроль прогресса и рост показателей")
    ]

    private let auroraPoints: [String] = [
        "Предсказывает доход на день и неделю",
        "Подбирает оптимальный график под ваши цели",
        "Считывает, сохраняет и анализирует заметки",
        "Учитывает состояние пользователя и нагрузку",
        "Рекомендует режим для максимальной продуктивности"
    ]

    var body: some View {
        ZStack {
            backgroundVisual

            VStack(spacing: 16) {
                TabView(selection: $currentPage) {
                    firstPage
                        .tag(0)

                    secondPage
                        .tag(1)

                    thirdPage
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // STYLE: Ограничивает высоту карточек онбординга для компактного вертикального ритма.
                .frame(maxHeight: 560)

                progressBar

                actionButtons
            }
            // STYLE: Общие внутренние отступы контента онбординга.
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .onAppear {
            startAuroraIfNeeded(reset: true)
        }
        .onChange(of: currentPage) { _, newPage in
            if newPage == 2 {
                startAuroraIfNeeded(reset: true)
            } else {
                stopAuroraAnimation()
            }
        }
        .onDisappear {
            stopAuroraAnimation()
        }
    }

    private var firstPage: some View {
        pageCard(
            title: "Основные функции",
            subtitle: "Смены, доходы, расходы и заметки всегда под рукой"
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(coreFeatures) { item in
                    infoTile(item: item)
                }
            }
            .padding(.top, 4)

            Image("OnboardingAIForecast")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                // STYLE: Фиксированная высота превью-иллюстрации первой страницы.
                .frame(height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 2)
        }
    }

    private var secondPage: some View {
        pageCard(
            title: "Геопозиция и рекомендации",
            subtitle: "Погода и локация помогают строить точный прогноз и рабочий ритм"
        ) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    compactStat(icon: "location.fill", title: "Локация", value: "Контекст района")
                    compactStat(icon: "cloud.sun.fill", title: "Погода", value: "Влияет на спрос")
                }

                ForEach(secondaryFeatures) { item in
                    listRow(item: item)
                }

                Image("OnboardingBestDaysHours")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    // STYLE: Фиксированная высота графика второй страницы.
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 2)
            }
            .padding(.top, 4)
        }
    }

    private var thirdPage: some View {
        pageCard(
            title: "Алгоритм Авроры",
            subtitle: "Кратко и по делу: как AI помогает зарабатывать больше"
        ) {
            HStack(alignment: .top, spacing: 12) {
                Image("TabIconAurora")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    // STYLE: Размер бренд-иконки Авроры в третьем экране.
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<visibleAuroraPoints, id: \.self) { index in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                // STYLE: Единый цвет маркера пункта AI-списка.
                                .foregroundColor(Color(red: 0.18, green: 0.48, blue: 1.0))
                            Text(auroraPoints[index])
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)

            Image("OnboardingFeedbackToAurora")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                // STYLE: Высота финального визуального блока на третьей странице.
                .frame(height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 2)
        }
    }

    private var backgroundVisual: some View {
        ZStack {
            if UIRuntimeConfig.lightweightInterface {
                Color("AppBackground")
                    .ignoresSafeArea()
            } else {
                // STYLE: Базовый цветовой слой фона.
                Color("AppBackground")
                    .ignoresSafeArea()

                Image("AppBackgroundArt")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    // STYLE: Разная интенсивность фон-арта для светлой/темной темы.
                    .opacity(colorScheme == .dark ? 0.16 : 0.24)

                AccentGradients.systemAdaptive(colorScheme: colorScheme)
                    // STYLE: Легкая цветовая вуаль поверх фона.
                    .opacity(colorScheme == .dark ? 0.38 : 0.30)
                    .ignoresSafeArea()
            }
        }
    }

    private func pageCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.primary)

            Text(subtitle)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            content()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // STYLE: Отступы контента внутри карточки страницы.
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                // STYLE: Полупрозрачная подложка карточки.
                .fill(Color("AppSurface").opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        // STYLE: Тонкая обводка карточки для контраста.
                        .stroke(Color("AppBorder").opacity(0.45), lineWidth: 1)
                )
        )
    }

    private func infoTile(item: OnboardingItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 30, height: 30)

            Text(item.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)

            Text(item.body)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        // STYLE: Минимальная высота тайла, чтобы сетка была ровной.
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                // STYLE: Нейтральный фон инфо-тайла.
                .fill(Color(uiColor: .secondarySystemFill))
        )
    }

    private func listRow(item: OnboardingItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)

                Text(item.body)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                // STYLE: Фоновая плашка строки списка.
                .fill(Color(uiColor: .secondarySystemFill))
        )
    }

    private func compactStat(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        // STYLE: Единый минимальный размер карточек мини-статистики.
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
        )
    }

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    // STYLE: Активная страница подсвечивается градиентом, неактивная — серым.
                    .fill(index <= currentPage ? AnyShapeStyle(AccentGradients.softVioletBlue) : AnyShapeStyle(Color(uiColor: .systemGray4)))
                    .frame(height: 8)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if currentPage == 2 {
                primaryButton(title: "Начать работу") {
                    onFinish(0)
                }

                secondaryButton(title: "Открыть Аврору") {
                    onFinish(2)
                }
            } else {
                HStack(spacing: 10) {
                    secondaryButton(title: "Пропустить") {
                        onFinish(0)
                    }

                    primaryButton(title: "Далее") {
                        performUIUpdate(.easeInOut(duration: 0.2)) {
                            currentPage = min(currentPage + 1, 2)
                        }
                    }
                }
            }
        }
    }

    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                // STYLE: Минимальная высота CTA-кнопки.
                .frame(minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        // STYLE: Градиент основной кнопки.
                        .fill(ctaGradient)
                )
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                // STYLE: Та же высота, что у primary-кнопки, для визуальной симметрии.
                .frame(minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        // STYLE: Нейтральный фон вторичной кнопки.
                        .fill(Color(uiColor: .secondarySystemFill))
                )
        }
        .buttonStyle(.plain)
    }

    private func startAuroraIfNeeded(reset: Bool = false) {
        guard currentPage == 2 else { return }

        if reset {
            visibleAuroraPoints = 0
        }

        auroraTask?.cancel()
        auroraTask = Task {
            for index in 0..<auroraPoints.count {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 220_000_000)
                await MainActor.run {
                    performUIUpdate(.easeInOut(duration: 0.18)) {
                        visibleAuroraPoints = index + 1
                    }
                }
            }
            await MainActor.run {
                auroraTask = nil
            }
        }
    }

    private func stopAuroraAnimation() {
        auroraTask?.cancel()
        auroraTask = nil
        visibleAuroraPoints = 0
    }
}

private struct OnboardingItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: String
}

#Preview {
    OnboardingView { _ in }
    
}
