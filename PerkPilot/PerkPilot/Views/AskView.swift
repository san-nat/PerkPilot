import SwiftUI
import SwiftData

// MARK: - AskView
//
// "Ask PerkPilot": conversational card recommendations. Type or speak —
// the parser extracts amount + category/merchant, the answerer checks
// expiring unused credits FIRST (they beat earn rates), then earn-rate
// ranking, and stacks the two into one short answer. Only his 12 cards
// are ever recommended. Voice is optional; typing always works.

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
    var answer: AskAnswer?
}

struct AskView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<CardItem> { !$0.isArchived }, sort: \CardItem.canonicalName)
    private var cards: [CardItem]
    @Query private var completions: [CompletionRecord]
    @Query private var mutes: [MutedReward]

    @StateObject private var speech = SpeechService()
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var pending: AskQuery?
    @State private var lastCategory: SpendCategory?
    @State private var lastMerchant: String?
    @State private var lastMerchantDisplay: String?
    @State private var voiceReplies = false
    @State private var selectedCard: CardItem?
    @State private var showingCardDetail = false
    @State private var showMicExplainer = false
    @State private var showMicDenied = false

    private var mutedIds: Set<String> { Set(mutes.map(\.benefitStableId)) }
    private var completedKeys: Set<String> { Set(completions.map(\.lookupKey)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if messages.isEmpty {
                                welcomeView
                            }
                            ForEach(messages) { message in
                                messageView(message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, PPTheme.screenPad)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                inputBar
            }
            .background(PPTheme.pageBackground)
            .navigationTitle("Ask")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        voiceReplies.toggle()
                        if !voiceReplies { speech.stopSpeaking() }
                    } label: {
                        Label("Voice replies", systemImage: voiceReplies ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        messages.removeAll()
                        pending = nil
                        speech.stopSpeaking()
                    } label: {
                        Label("Clear chat", systemImage: "trash")
                    }
                    .disabled(messages.isEmpty)
                }
            }
            .sheet(isPresented: $showingCardDetail) {
                if let card = selectedCard {
                    NavigationStack { CardDetailView(card: card) }
                }
            }
            .sheet(isPresented: $showMicExplainer) { micExplainer }
            .alert("Microphone unavailable", isPresented: $showMicDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("PerkPilot doesn't have microphone access. Enable it in Settings → PerkPilot → Microphone, or just type your question.")
            }
            .onAppear {
                speech.onFinalTranscript = { transcript in
                    send(transcript, fromVoice: true)
                }
            }
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        BentoTile {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ask about any purchase")
                    .font(.headline)
                Text("I'll check your expiring credits first — an unused credit beats any earn rate — then rank your cards.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(Self.suggestions, id: \.self) { s in
                    Button {
                        send(s, fromVoice: false)
                    } label: {
                        Text(s)
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(PPTheme.gold.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Text("Tap the mic to speak — typing always works too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static let suggestions = [
        "$200 restaurant spend — which card?",
        "$400 gym membership — which card?",
        "Where should I buy gas?",
    ]

    // MARK: - Messages

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey(message.text))
                    .font(.body)
                if let answer = message.answer {
                    creditsSection(answer)
                    rankingSection(answer)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PPTheme.tileBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PPTheme.hairline, lineWidth: 1)
            )
            .padding(.trailing, 48)
        }
    }

    private func creditsSection(_ answer: AskAnswer) -> some View {
        Group {
            if !answer.credits.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("EXPIRING CREDITS TO BURN")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    ForEach(answer.credits, id: \.benefit.stableId) { match in
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(PPTheme.gold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(shortName(match.card)): \(match.benefit.amountDisplay) \(match.benefit.name)")
                                    .font(.subheadline).fontWeight(.medium)
                                Text("Unused for \(match.periodLabel)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func rankingSection(_ answer: AskAnswer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EARN RANKING")
                .font(.caption2).fontWeight(.semibold)
                .foregroundStyle(.secondary)
            ForEach(Array(answer.ranked.enumerated()), id: \.element.cardStableId) { i, card in
                Button {
                    if let item = cards.first(where: { $0.stableId == card.cardStableId }) {
                        selectedCard = item
                        showingCardDetail = true
                    }
                } label: {
                    HStack {
                        Text("\(i + 1).").font(.subheadline).foregroundStyle(.secondary)
                        Text(card.displayName).font(.subheadline).fontWeight(.medium)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(card.rewardUSD, format: .currency(code: "USD"))
                                .font(.subheadline).fontWeight(.bold).monospacedDigit()
                            Text(card.rateLabel)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Estimates — point values are conservative.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func shortName(_ card: CardItem) -> String {
        RewardsAdvisor.profiles[card.stableId]?.shortName ?? card.canonicalName
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(spacing: 6) {
            if speech.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .opacity(speech.isRecording ? 1 : 0.3)
                    Text(speech.liveTranscript.isEmpty ? "Listening…" : speech.liveTranscript)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, PPTheme.screenPad)
            }
            HStack(spacing: 10) {
                Button {
                    micTapped()
                } label: {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundStyle(speech.isRecording ? .red : .blue)
                }
                .disabled(!speech.isAvailable && speech.authState != .notDetermined)
                TextField("Ask — $200 dinner, which card?", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { sendInput() }
                    .disabled(speech.isRecording)
                Button {
                    sendInput()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || speech.isRecording)
            }
            .padding(.horizontal, PPTheme.screenPad)
            .padding(.vertical, 10)
            .background(PPTheme.tileBackground)
        }
    }

    private func sendInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        send(text, fromVoice: false)
    }

    // MARK: - Conversation logic

    private func send(_ text: String, fromVoice: Bool) {
        messages.append(ChatMessage(role: .user, text: text))
        var query = AskParser.parse(text)
        // Carry over the last known category when the user follows up with
        // just an amount ("what about $300?").
        if pending == nil, query.category == nil, query.amount != nil, let last = lastCategory {
            query.category = last
            query.merchant = lastMerchant
            query.merchantDisplay = lastMerchantDisplay
        }
        if let p = pending {
            query = p.merged(with: query)
        }
        if let question = query.clarifyingQuestion {
            pending = query
            messages.append(ChatMessage(role: .assistant, text: question))
            return
        }
        pending = nil
        lastCategory = query.category
        lastMerchant = query.merchant
        lastMerchantDisplay = query.merchantDisplay
        let txs = TransactionStore.transactions(context: context)
        let ytd = RewardsAdvisor.ytdSpendByCardCategory(txs)
        if let answer = AskAnswerer.answer(
            query: query, cards: cards,
            mutedIds: mutedIds, completedKeys: completedKeys, ytd: ytd
        ) {
            messages.append(ChatMessage(role: .assistant, text: answer.headline, answer: answer))
            if fromVoice && voiceReplies {
                speech.speak(answer.headline)
            }
        } else {
            messages.append(ChatMessage(
                role: .assistant,
                text: "I couldn't quite parse that. Try something like \"$200 restaurant spend — which card?\""
            ))
        }
    }

    // MARK: - Mic

    private func micTapped() {
        switch speech.authState {
        case .notDetermined:
            showMicExplainer = true
        case .denied:
            showMicDenied = true
        case .authorized, .requesting:
            speech.toggleRecording()
        }
    }

    private var micExplainer: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                BentoTile {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Voice input", systemImage: "mic.fill")
                            .font(.headline)
                        Text("PerkPilot can transcribe your spoken questions so you can ask hands-free, like \"$200 dinner — which card?\"")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Privacy note: transcription happens through Apple's speech service, which may process short audio clips on Apple servers. Your cards, statements, and answers never leave this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Enable microphone") {
                    showMicExplainer = false
                    speech.requestPermissions { granted in
                        if granted { speech.toggleRecording() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
            .padding(PPTheme.screenPad)
            .background(PPTheme.pageBackground)
            .navigationTitle("Voice input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { showMicExplainer = false }
                }
            }
        }
    }
}
