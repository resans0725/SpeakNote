import SwiftUI
import Speech
import AVFoundation
import AppTrackingTransparency

// MARK: - Model
struct Transcription: Identifiable, Codable {
    let id = UUID()
    let text: String
    let timestamp: Date
}

// MARK: - ViewModel
class SpeechViewModel: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var transcriptionText: String = ""
    @Published var transcriptionHistory: [Transcription] = []
    @Published var isSpeechRecognitionAvailable: Bool = false
    @Published var errorMessage: String?
    @Published var showSaveAlert: Bool = false
    @Published var showDeleteAlert: Bool = false
    @Published var showClearAllAlert: Bool = false
    @Published var transcriptionToDelete: Transcription?
    @Published var showSettingsAlert: Bool = false // Added for settings dialog
    
    @StateObject var ads = AdManager.shared
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja_JP"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private let userDefaults = UserDefaults.standard
    
    init() {
        loadHistory()
    }
    
    func checkSpeechRecognitionPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isSpeechRecognitionAvailable = status == .authorized
            }
        }
    }
    
    func startRecording() {
        guard isSpeechRecognitionAvailable else {
            DispatchQueue.main.async {
                self.showSettingsAlert = true // Show settings alert instead of error message
            }
            return
        }
        
        cleanup()
        
        isRecording = true
        transcriptionText = ""
        errorMessage = nil
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine!.inputNode
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result = result {
                    self?.transcriptionText = result.bestTranscription.formattedString
                } else if let error = error {
                    self?.errorMessage = "音声認識リクエストがキャンセルされました: \(error.localizedDescription)"
                    self?.stopRecording()
                }
            }
        }
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            
            audioEngine?.prepare()
            try audioEngine?.start()
        } catch {
            errorMessage = "録音開始に失敗しました: \(error.localizedDescription)"
            isRecording = false
            cleanup()
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        cleanup()
        
        if !transcriptionText.isEmpty {
            DispatchQueue.main.async {
                self.showSaveAlert = true
            }
        }
    }
    
    func saveTranscription() {
        if !transcriptionText.isEmpty {
            let newTranscription = Transcription(text: transcriptionText, timestamp: Date())
            transcriptionHistory.append(newTranscription)
            if let data = try? JSONEncoder().encode(transcriptionHistory) {
                userDefaults.set(data, forKey: "transcriptionHistory")
            }
        }
        transcriptionText = ""
        
        if let root = topViewController() {
            ads.showInterstitial(from: root)
        }
    }
    
    private func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
    
    private func cleanup() {
        recognitionTask?.finish()
        recognitionTask = nil
        
        if let audioEngine = audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "オーディオセッションの終了に失敗しました: \(error.localizedDescription)"
        }
    }
    
    func loadHistory() {
        if let data = userDefaults.data(forKey: "transcriptionHistory"),
           let history = try? JSONDecoder().decode([Transcription].self, from: data) {
            transcriptionHistory = history
        }
    }
    
    func deleteTranscription(_ transcription: Transcription) {
        transcriptionHistory.removeAll { $0.id == transcription.id }
        if let data = try? JSONEncoder().encode(transcriptionHistory) {
            userDefaults.set(data, forKey: "transcriptionHistory")
        }
    }
    
    func clearHistory() {
        transcriptionHistory = []
        userDefaults.removeObject(forKey: "transcriptionHistory")
    }
    
    func copyTranscription(_ text: String) {
        UIPasteboard.general.string = text
    }
}

// MARK: - Color Theme
extension Color {
    static let primaryGradientStart = Color(red: 0.2, green: 0.4, blue: 0.8)
    static let primaryGradientEnd = Color(red: 0.3, green: 0.6, blue: 1.0)
    static let recordingGradientStart = Color(red: 0.8, green: 0.2, blue: 0.3)
    static let recordingGradientEnd = Color(red: 1.0, green: 0.4, blue: 0.5)
    static let accentColor = Color(red: 0.9, green: 0.3, blue: 0.4)
    static let backgroundColor = Color(red: 1.0, green: 1.0, blue: 1.0)
    static let cardBackground = Color(red: 1.0, green: 1.0, blue: 1.0)
}

// MARK: - Views
struct ContentView: View {
    @StateObject private var viewModel = SpeechViewModel()
    @State private var micScale: CGFloat = 1.0
    @State private var isShowingHistory = false
    @State var isShowSplashView = true
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0.0
    
    var homeBannerID: String {
    #if DEBUG
    return "ca-app-pub-3940256099942544/2934735716"// テスト広告ID
    #else
    return "ca-app-pub-1909140510546146/7790750676"
    #endif
    }
    
    var body: some View {
        if isShowSplashView {
            splashView
        } else {
            NavigationView {
                ZStack {
                    Color.backgroundColor.edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 20) {
                        // Transcription Display
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.cardBackground)
                                .shadow(color: .gray.opacity(0.2), radius: 10, x: 5, y: 5)
                                .shadow(color: .white.opacity(0.7), radius: 10, x: -5, y: -5)
                            
                            if viewModel.transcriptionText.isEmpty {
                                Text("マイクをタップして開始")
                                    .font(.system(size: 18, weight: .medium, design: .rounded))
                                    .foregroundColor(.primary)
                                    .padding()
                                    .multilineTextAlignment(.center)
                                    .lineLimit(nil) // 全文表示
                            } else {
                                ScrollView {
                                    Text(viewModel.transcriptionText)
                                        .font(.system(size: 18, weight: .medium, design: .rounded))
                                        .foregroundColor(.primary)
                                        .padding()
                                        .multilineTextAlignment(.center)
                                        .lineLimit(nil) // 全文表示
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 350) // 高さ範囲を指定
                        .padding(.horizontal)
                        .animation(.easeInOut, value: viewModel.transcriptionText)
                        
                        // Error Message
                        if let error = viewModel.errorMessage {
                            Text("エラー: \(error)")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                                .transition(.opacity)
                        }
                        
                        // Microphone Button
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                if viewModel.isRecording {
                                    viewModel.stopRecording()
                                } else {
                                    viewModel.startRecording()
                                }
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: viewModel.isRecording ? [.recordingGradientStart, .recordingGradientEnd] : [.primaryGradientStart, .primaryGradientEnd]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                    .scaleEffect(micScale)
                                    .shadow(color: .gray.opacity(0.3), radius: 10, x: 5, y: 5)
                                
                                Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .onChange(of: viewModel.isRecording) {
                            if viewModel.isRecording {
                                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                    micScale = 1.2
                                }
                            } else {
                                withAnimation {
                                    micScale = 1.0
                                }
                            }
                        }
                        
                        // History Button
                        NavigationLink(
                            destination: HistoryView(viewModel: viewModel),
                            isActive: $isShowingHistory
                        ) {
                            Text("履歴を見る")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.primaryGradientStart, .primaryGradientEnd]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(15)
                                .padding(.horizontal)
                        }
                        
                        BannerAdView(bannerID: homeBannerID)
                            .frame(width: UIScreen.main.bounds.width - 70)
                            .frame(height: 50)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 12)
                    }
                    .padding(.vertical)
                    .alert(isPresented: $viewModel.showSaveAlert) {
                        Alert(
                            title: Text("文字起こしを保存"),
                            message: Text("この文字起こしを履歴に保存しますか？"),
                            primaryButton: .default(Text("保存")) {
                                viewModel.saveTranscription()
                            },
                            secondaryButton: .cancel(Text("キャンセル")) {
                                viewModel.transcriptionText = ""
                            }
                        )
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("SpeakNote")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primaryGradientStart)
                    }
                }
            }
            .onAppear {
                viewModel.checkSpeechRecognitionPermission()
                viewModel.ads.loadInterstitial()
            }
            .alert(isPresented: $viewModel.showSettingsAlert) { // Added settings alert
                Alert(
                    title: Text("音声認識の許可が必要です"),
                    message: Text("音声認識を使用するには、設定でマイクと音声認識のアクセスを許可してください。"),
                    primaryButton: .default(Text("設定を開く")) {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    },
                    secondaryButton: .cancel(Text("キャンセル"))
                )
            }
        }
    }
    
    var splashView: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.7)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: -20) {
                Image(.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .shadow(radius: 10)

                Image(.iconTitle)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                requestTrackingPermissionIfNeeded()
            }
        }
    }
    
    func requestTrackingPermissionIfNeeded() {
        ATTrackingManager.requestTrackingAuthorization { status in
            switch status {
            case .authorized:
                print("Tracking authorized")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    withAnimation {
                        self.isShowSplashView = false
                    }
                }
            case .denied, .restricted:
                print("Tracking denied")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    withAnimation {
                        self.isShowSplashView = false
                    }
                }
            case .notDetermined:
                print("Not determined – まだダイアログが出ていません")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    withAnimation {
                        self.isShowSplashView = true
                    }
                }
            @unknown default:
                break
            }
        }
    }
}

struct HistoryView: View {
    @ObservedObject var viewModel: SpeechViewModel
    
    var historyBannerID: String {
    #if DEBUG
    return "ca-app-pub-3940256099942544/2934735716"// テスト広告ID
    #else
    return "ca-app-pub-1909140510546146/1119199414"
    #endif
    }
    
    
    var body: some View {
        ZStack {
            Color.backgroundColor.edgesIgnoringSafeArea(.all)
            
            VStack {
                if viewModel.transcriptionHistory.isEmpty {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("文字起こし履歴はありません")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(.primary)
                                .lineLimit(3)
                        }
                        .padding()
                        
                        Spacer()
                    }
                    .navigationTitle("文字起こし履歴")
                    .navigationBarTitleDisplayMode(.inline)
                    .padding(.vertical, 4)
                    
                    Spacer()
                } else {
                    List {
                        ForEach(viewModel.transcriptionHistory) { transcription in
                            NavigationLink(
                                destination: TranscriptionDetailView(viewModel: viewModel, transcription: transcription)
                            ) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(Color.cardBackground)
                                        .shadow(color: .gray.opacity(0.2), radius: 5, x: 3, y: 3)
                                        .shadow(color: .white.opacity(0.7), radius: 5, x: -3, y: -3)
                                    
                                    HStack {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(transcription.text)
                                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                                .foregroundColor(.primary)
                                                .lineLimit(3)
                                            
                                            Text(transcription.timestamp, style: .date)
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        .padding()
                                        
                                        Spacer()
                                    }
                                    
                                    
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .navigationTitle("文字起こし履歴")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem {
                            Button(action: {
                                viewModel.showClearAllAlert = true
                            }) {
                                Text("全履歴をクリア")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .alert(isPresented: $viewModel.showClearAllAlert) {
                        Alert(
                            title: Text("全履歴を削除"),
                            message: Text("すべての履歴を削除しますか？この操作は元に戻せません。"),
                            primaryButton: .destructive(Text("削除")) {
                                withAnimation {
                                    viewModel.clearHistory()
                                }
                            },
                            secondaryButton: .cancel(Text("キャンセル"))
                        )
                    }
                }
                
                BannerAdView(bannerID: historyBannerID)
                    .frame(width: UIScreen.main.bounds.width - 70)
                    .frame(height: 50)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 12)
            }
        }
    }
}

struct TranscriptionDetailView: View {
    @ObservedObject var viewModel: SpeechViewModel
    let transcription: Transcription
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.backgroundColor.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // Transcription Text
                ScrollView {
                    Text(transcription.text)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.cardBackground)
                        .cornerRadius(15)
                        .shadow(color: .gray.opacity(0.2), radius: 5, x: 3, y: 3)
                        .padding(.horizontal)
                        .lineLimit(nil)
                }
                
                // Timestamp
                Text(transcription.timestamp, style: .date)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                // Copy Button
                Button(action: {
                    viewModel.copyTranscription(transcription.text)
                }) {
                    Text("テキストをコピー")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.primaryGradientStart, .primaryGradientEnd]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        .padding(.horizontal)
                }
                
                // Delete Button
                Button(action: {
                    viewModel.transcriptionToDelete = transcription
                    viewModel.showDeleteAlert = true
                }) {
                    Text("この履歴を削除")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .navigationTitle("文字起こし詳細")
            .navigationBarTitleDisplayMode(.inline)
            .alert(isPresented: $viewModel.showDeleteAlert) {
                Alert(
                    title: Text("履歴を削除"),
                    message: Text("この文字起こしを削除しますか？この操作は元に戻せません。"),
                    primaryButton: .destructive(Text("削除")) {
                        if let transcription = viewModel.transcriptionToDelete {
                            withAnimation {
                                viewModel.deleteTranscription(transcription)
                            }
                            dismiss()
                        }
                    },
                    secondaryButton: .cancel(Text("キャンセル")) {
                        viewModel.transcriptionToDelete = nil
                    }
                )
            }
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
