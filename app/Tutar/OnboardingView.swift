// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedPage = OnboardingPage.welcome.rawValue

    private let pages = OnboardingPage.allCases

    var body: some View {
        VStack(spacing: 0) {
            skipBar

            GeometryReader { geometry in
                TabView(selection: $selectedPage) {
                    ForEach(pages) { page in
                        ScrollView {
                            pageContent(page)
                                .frame(maxWidth: 580)
                                .frame(
                                    minHeight: geometry.size.height,
                                    alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center
                                )
                                .frame(maxWidth: .infinity)
                        }
                        .scrollIndicators(.hidden)
                        .tag(page.rawValue)
                        .accessibilityIdentifier("onboardingPage-\(page.rawValue)")
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            pageIndicator
                .padding(.top, 12)

            navigationControls
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .safeAreaPadding(.top, 4)
        .safeAreaPadding(.bottom, 8)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var skipBar: some View {
        HStack {
            Spacer()
            if selectedPage < pages.count - 1 {
                Button("onboarding.skip", action: onFinish)
                    .buttonStyle(.plain)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("onboardingSkipButton")
            } else {
                Text("onboarding.skip")
                    .font(.callout.weight(.medium))
                    .frame(minWidth: 44, minHeight: 44)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
    }

    private func pageContent(_ page: OnboardingPage) -> some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 16 : 26) {
            if page == .welcome {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: visualSize, height: visualSize)
                    .clipShape(RoundedRectangle(cornerRadius: visualSize * 0.23, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: page.symbol)
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 44 : 58, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
                    .frame(width: visualSize, height: visualSize)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                Text(page.message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 28)
        .accessibilityElement(children: .contain)
    }

    private var visualSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 68 : 96
    }

    private var pageIndicator: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                ForEach(pages) { page in
                    Capsule(style: .continuous)
                        .fill(page.rawValue == selectedPage ? Color.primary : Color(.tertiarySystemFill))
                        .frame(width: page.rawValue == selectedPage ? 24 : 8, height: 8)
                }
            }
            .accessibilityHidden(true)

            Text(verbatim: "\(selectedPage + 1) / \(pages.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(verbatim: AppFormat.format(
                    "onboarding.page.accessibility",
                    language: language,
                    selectedPage + 1,
                    pages.count
                )))
                .accessibilityIdentifier("onboardingPagePosition")
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedPage)
    }

    @ViewBuilder
    private var navigationControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                if selectedPage > 0 { backButton }
                primaryButton
            }
        } else {
            HStack(spacing: 12) {
                if selectedPage > 0 {
                    backButton
                    Spacer(minLength: 12)
                }
                primaryButton
            }
        }
    }

    private var backButton: some View {
        Button {
            move(to: selectedPage - 1)
        } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(Text("onboarding.back"))
        .accessibilityIdentifier("onboardingBackButton")
    }

    private var primaryButton: some View {
        Button {
            if selectedPage == pages.count - 1 {
                onFinish()
            } else {
                move(to: selectedPage + 1)
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedPage == pages.count - 1 ? "onboarding.start" : "onboarding.next")
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.center)
                if selectedPage < pages.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Color(.systemBackground))
            .padding(.horizontal, 22)
            .frame(minHeight: 48)
            .background(Color.primary, in: Capsule(style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(selectedPage == pages.count - 1
            ? "onboarding.start"
            : "onboarding.next"))
        .accessibilityIdentifier(selectedPage == pages.count - 1
            ? "onboardingFinishButton"
            : "onboardingNextButton")
    }

    private func move(to page: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            selectedPage = page
        }
    }
}

private enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome
    case planning
    case budgets
    case savings
    case privacy

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .welcome: "onboarding.welcome.title"
        case .planning: "onboarding.planning.title"
        case .budgets: "onboarding.budgets.title"
        case .savings: "onboarding.savings.title"
        case .privacy: "onboarding.privacy.title"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .welcome: "onboarding.welcome.message"
        case .planning: "onboarding.planning.message"
        case .budgets: "onboarding.budgets.message"
        case .savings: "onboarding.savings.message"
        case .privacy: "onboarding.privacy.message"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: ""
        case .planning: "repeat"
        case .budgets: "chart.pie"
        case .savings: "building.columns"
        case .privacy: "lock.shield"
        }
    }
}
