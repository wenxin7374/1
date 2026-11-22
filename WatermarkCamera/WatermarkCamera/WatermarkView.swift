import SwiftUI

/// 取景界面左下角的实时水印，点击时间/备注分别进入编辑。
struct WatermarkOverlay: View {
    @ObservedObject var settings: SettingsStore
    let timeText: String

    @State private var showingNote = false
    @State private var showingTime = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { showingTime = true } label: {
                Text(timeText)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.75), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(.plain)

            if settings.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // 仅取景界面显示提示，为空时最终照片不写入任何备注或「备注：」标签。
                Button { showingNote = true } label: {
                    Text("+ 添加备注")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.75))
                        .shadow(color: .black.opacity(0.7), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            } else {
                Button { showingNote = true } label: {
                    Text(WatermarkRenderer.displayNote(settings.note))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.75), radius: 3, x: 0, y: 1)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 300, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingNote) {
            NoteEditorView(settings: settings)
        }
        .sheet(isPresented: $showingTime) {
            TimeEditorView(settings: settings)
        }
    }
}

// MARK: - 备注编辑

struct NoteEditorView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(settings: SettingsStore) {
        self.settings = settings
        _text = State(initialValue: settings.note)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $text)
                    .font(.body)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .onChange(of: text) { newValue in
                        if newValue.count > 100 {
                            text = String(newValue.prefix(100))
                        }
                    }
                Text("\(text.count)/100")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding()
            .navigationTitle("水印备注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("清空") {
                        text = ""
                        settings.note = ""
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        settings.note = text
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 时间编辑

struct TimeEditorView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var datePart: Date
    @State private var seconds: Int

    init(settings: SettingsStore) {
        self.settings = settings
        let base = settings.timeMode == .custom ? settings.customDate : Date()
        _datePart = State(initialValue: base)
        _seconds = State(initialValue: Calendar.current.component(.second, from: base))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                DatePicker("日期与时间", selection: $datePart,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel)
                    .labelsHidden()

                HStack {
                    Text("秒").foregroundColor(.secondary)
                    Picker("秒", selection: $seconds) {
                        ForEach(0..<60) { value in
                            Text(String(format: "%02d", value)).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 100)
                }

                Button("恢复当前时间") {
                    settings.resetToCurrentTime()
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("水印时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        var components = Calendar.current.dateComponents(
                            [.year, .month, .day, .hour, .minute], from: datePart
                        )
                        components.second = seconds
                        settings.customDate = Calendar.current.date(from: components) ?? datePart
                        settings.timeMode = .custom
                        dismiss()
                    }
                }
            }
        }
    }
}
