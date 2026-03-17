import SwiftUI

struct NumberField: View {
    let title: String
    @Binding var value: Double
    let currency: String?
    let onEditingEnd: ((Double) -> Void)?
    let showsKeyboardToolbar: Bool

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    init(
        title: String,
        value: Binding<Double>,
        currency: String? = nil,
        showsKeyboardToolbar: Bool = true,
        onEditingEnd: ((Double) -> Void)? = nil
    ) {
        self.title = title
        self._value = value
        self.currency = currency
        self.showsKeyboardToolbar = showsKeyboardToolbar
        self.onEditingEnd = onEditingEnd
    }

    @ViewBuilder
    var body: some View {
        let content = HStack {
            if !title.isEmpty {
                Text(title)
                    // STYLE: Цвет и размер подписи поля.
                    .foregroundColor(AppColors.text)
                    .font(.subheadline)
            }

            Spacer()

            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                // STYLE: Фиксированная ширина поля суммы.
                .frame(width: 80)
                // STYLE: Системная рамка вокруг текстового поля.
                .textFieldStyle(RoundedBorderTextFieldStyle())
                // STYLE: Акцентный цвет курсора и активного состояния.
                .accentColor(AppColors.accent)
                .focused($isFocused)
                .onChange(of: text) { newValue in
                    let filtered = newValue.filter { $0.isNumber || $0 == "." || $0 == "," }
                    if filtered != newValue { text = filtered }
                    let normalized = text.replacingOccurrences(of: ",", with: ".")
                    if let number = Double(normalized) {
                        value = number
                    } else if text.isEmpty {
                        value = 0
                    }
                }
                .onAppear {
                    text = value == 0 ? "" : String(format: "%.0f", value)
                }
                .onChange(of: value) { newValue in
                    if !isFocused {
                        text = newValue == 0 ? "" : String(format: "%.0f", newValue)
                    }
                }
                .onChange(of: isFocused) { focused in
                    if !focused {
                        onEditingEnd?(value)
                    }
                }

            if let currency = currency {
                Text(currency)
                    // STYLE: Вторичный цвет валютного суффикса.
                    .foregroundColor(AppColors.secondaryText)
                    .font(.subheadline)
            }
        }

        if showsKeyboardToolbar {
            content
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(NSLocalizedString("Готово", comment: "number field keyboard done")) {
                            isFocused = false
                        }
                    }
                }
        } else {
            content
        }
    }
}
