import SwiftUI

struct ToastView: View {
    let toast: Toast

    var body: some View {
        Text(toast.text)
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(toast.isError ? Color.red : Color.black.opacity(0.85))
            )
            .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
            .padding(.horizontal, 24)
            .padding(.bottom, 96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    func toastOverlay(_ toast: Binding<Toast?>) -> some View {
        overlay(alignment: .bottom) {
            if let current = toast.wrappedValue {
                ToastView(toast: current)
                    .task(id: current.id) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if toast.wrappedValue?.id == current.id {
                                toast.wrappedValue = nil
                            }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast.wrappedValue)
    }
}
