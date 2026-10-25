import FileTermCore
import SwiftUI

struct ChecksumUtilityView: View {
  @Bindable var model: ChecksumUtilityModel
  let close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("File Checksum").font(.headline)
      Text(model.url.path).font(.callout).textSelection(.enabled)
        .lineLimit(3).help(model.url.path)
      Picker("Algorithm", selection: $model.algorithm) {
        ForEach(ChecksumAlgorithm.allCases, id: \.self) { algorithm in
          Text(algorithm.utilityTitle).tag(algorithm)
        }
      }
      .disabled(model.isRunning)
      if model.isRunning {
        ProgressView(value: model.fractionCompleted)
          .accessibilityLabel("Checksum progress")
        Text(model.progressDescription).font(.caption).foregroundStyle(.secondary)
      }
      if let digest = model.digest {
        Text(digest).font(.system(.body, design: .monospaced))
          .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("checksumResult")
      }
      TextField("Expected checksum (optional)", text: $model.expectedDigest)
        .textFieldStyle(.roundedBorder).accessibilityIdentifier("checksumCompare")
      if let comparison = model.comparisonDescription {
        Label(comparison, systemImage: model.checksumMatches ? "checkmark.circle" : "xmark.circle")
          .accessibilityIdentifier("checksumComparison")
      }
      if let message = model.message {
        Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
      }
      Text("MD5 and SHA-1 are compatibility checksums, not secure authentication methods.")
        .font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Copy Checksum") { model.copyDigest() }.disabled(model.digest == nil)
        Spacer()
        if model.isRunning {
          Button("Cancel") { model.cancel() }.keyboardShortcut(.cancelAction)
        } else {
          Button("Close", action: close).keyboardShortcut(.cancelAction)
        }
        Button("Calculate") { model.calculate() }
          .keyboardShortcut(.defaultAction).disabled(model.isRunning)
      }
    }.padding(20).frame(width: 520)
      .onChange(of: model.algorithm) { _, _ in model.clearResult() }
  }
}

struct FolderSizesUtilityView: View {
  let model: FolderSizesUtilityModel
  let close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Calculate All Folder Sizes").font(.headline)
      Text(model.rootPath).font(.callout).textSelection(.enabled).lineLimit(3)
      ProgressView(value: Double(model.completedCount), total: Double(max(1, model.totalCount)))
        .accessibilityLabel("Folder size progress")
      Text("\(model.completedCount) of \(model.totalCount) folders calculated")
        .monospacedDigit()
      if !model.currentName.isEmpty {
        Text(model.currentName).font(.callout).lineLimit(1).truncationMode(.middle)
      }
      Text(model.progressDescription).font(.caption).foregroundStyle(.secondary)
      if let message = model.message {
        Text(message).font(.callout).textSelection(.enabled)
      }
      if !model.failures.isEmpty {
        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(model.failures.enumerated()), id: \.offset) { _, failure in
              Label(failure, systemImage: "exclamationmark.triangle")
                .font(.caption).textSelection(.enabled)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: 140)
      }
      Text(
        "Sizes include folder contents. Symbolic links are not followed. Completed results remain visible if cancelled."
      )
      .font(.caption).foregroundStyle(.secondary)
      HStack {
        Spacer()
        if model.isRunning {
          Button("Cancel") { model.cancel() }.keyboardShortcut(.cancelAction)
        } else {
          Button("Close", action: close).keyboardShortcut(.defaultAction)
        }
      }
    }.padding(20).frame(width: 480)
  }
}

extension ChecksumAlgorithm {
  var utilityTitle: String {
    switch self {
    case .md5: "MD5"
    case .sha1: "SHA-1"
    case .sha256: "SHA-256"
    }
  }
}
