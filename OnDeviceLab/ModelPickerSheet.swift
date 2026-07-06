import SwiftUI

/// The model-choice sheet presented from ContentView's model trigger.
struct ModelPickerSheet: View {
    let models: [LabModel]
    @Binding var selection: LabModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Choose a model")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.top, 18).padding(.bottom, 14)

            VStack(spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    optionRow(model)
                    if index < models.count - 1 {
                        Hairline().padding(.leading, 16)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(DS.background)
        .presentationDetents([.height(CGFloat(models.count) * 86 + 96)])
        .presentationDragIndicator(.visible)
    }

    private func optionRow(_ model: LabModel) -> some View {
        let isSelected = model.id == selection.id
        return Button {
            selection = model
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Text(model.note)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold)).foregroundStyle(DS.accent)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? DS.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
