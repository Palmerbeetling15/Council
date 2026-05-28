import SwiftUI

/// First-run configuration: pick a persona + LLM for each of the three seats
/// and enter the API keys. Keys go straight into the Keychain on save.
struct SetupView: View {
    @Bindable var store: CouncilStore
    var onDone: () -> Void

    // Live text of each seat's key field, keyed by seat id.
    @State private var keyDrafts: [Int: String] = [:]

    var body: some View {
        VStack(spacing: 24) {
            Text("Council'ı Kur")
                .font(.largeTitle.bold())

            Text("Koltukları doldur: karakter, LLM ve API key. En az bir key yeter — boş kalan koltuk sadece o soruda hata gösterir.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(alignment: .top, spacing: 20) {
                ForEach($store.seats) { $seat in
                    SeatConfigCard(seat: $seat, keyDraft: keyBinding(for: seat.id))
                }
            }

            Spacer()

            Button("Kaydet ve Devam Et") {
                saveAll()
                onDone()
            }
            .controlSize(.large)
            .keyboardShortcut(.return)
            .disabled(!canProceed)
        }
        .padding(40)
        .frame(minWidth: 960, minHeight: 640)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .onAppear(perform: loadDrafts)
    }

    private func keyBinding(for id: Int) -> Binding<String> {
        Binding(
            get: { keyDrafts[id] ?? "" },
            set: { keyDrafts[id] = $0 }
        )
    }

    /// Enabled once at least one seat is usable (has a key, or is key-free).
    private var canProceed: Bool {
        store.seats.contains { seat in
            guard seat.provider.requiresAPIKey else { return true }
            return !(keyDrafts[seat.id] ?? "").isEmpty
        }
    }

    private func loadDrafts() {
        for seat in store.seats where seat.provider.requiresAPIKey {
            keyDrafts[seat.id] = (try? KeychainStore.read(account: seat.provider.keychainAccount)) ?? ""
        }
    }

    private func saveAll() {
        for seat in store.seats where seat.provider.requiresAPIKey {
            let key = (keyDrafts[seat.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                try? KeychainStore.save(key, account: seat.provider.keychainAccount)
            }
        }
        store.saveSeats()
    }
}

private struct SeatConfigCard: View {
    @Binding var seat: Seat
    @Binding var keyDraft: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Karakter", selection: $seat.archetype) {
                ForEach(Archetype.allCases) { Text($0.displayName).tag($0) }
            }

            Picker("LLM", selection: $seat.provider) {
                ForEach(LLMProvider.allCases) { Text($0.displayName).tag($0) }
            }

            if seat.provider.requiresAPIKey {
                SecureField("API key", text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text("Key gerekmez (on-device)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(seat.archetype.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 240, height: 280, alignment: .topLeading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12))
        )
    }
}

#Preview {
    SetupView(store: CouncilStore(), onDone: {})
}
