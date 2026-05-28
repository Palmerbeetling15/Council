//
//  ContentView.swift
//  Council
//

import SwiftUI

struct ContentView: View {
    let store: CouncilStore
    @State private var showSetup: Bool
    @State private var query: String = ""
    @State private var isAsking = false

    init(store: CouncilStore) {
        self.store = store
        _showSetup = State(initialValue: !store.isConfigured)
    }

    var body: some View {
        Group {
            if showSetup {
                SetupView(store: store) { showSetup = false }
            } else {
                mainView
            }
        }
        .preferredColorScheme(.dark)
    }

    private var mainView: some View {
        VStack(spacing: 28) {
            HStack {
                Text("Council")
                    .font(.title2.bold())
                Spacer()
                Button {
                    showSetup = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Kurulumu düzenle (karakter / LLM / key)")
            }

            HStack(alignment: .top, spacing: 20) {
                ForEach(store.seats) { seat in
                    SeatCard(seat: seat, response: store.responses[seat.id] ?? .idle)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                TextField("Council'a bir soru sor…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit(ask)

                Button("Sor", action: ask)
                    .controlSize(.large)
                    .keyboardShortcut(.return)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isAsking)
            }
        }
        .padding(40)
        .frame(minWidth: 960, minHeight: 680)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
    }

    private func ask() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isAsking else { return }
        isAsking = true
        Task {
            await store.ask(q)
            isAsking = false
        }
    }
}

private struct SeatCard: View {
    let seat: Seat
    let response: SeatResponse

    var body: some View {
        VStack(spacing: 10) {
            Text(seat.archetype.displayName)
                .font(.headline)
            Text(seat.provider.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().opacity(0.3)

            responseArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(width: 260, height: 380, alignment: .top)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12))
        )
    }

    @ViewBuilder private var responseArea: some View {
        switch response {
        case .idle:
            Text("Soru bekleniyor…")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 24)
        case .text(let text):
            ScrollView {
                Text(text)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        case .failed(let message):
            ScrollView {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview {
    ContentView(store: CouncilStore())
}
