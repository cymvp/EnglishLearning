import SwiftUI
import PhotosUI

struct PhotoCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var showOCRResult = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                if let image = capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()

                    Button {
                        showOCRResult = true
                    } label: {
                        Label("识别单词", systemImage: "text.viewfinder")
                            .font(.title3)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                } else {
                    ContentUnavailableView {
                        Label("选择图片", systemImage: "photo.on.rectangle")
                    } description: {
                        Text("拍照或从相册选择一张包含英语单词的图片")
                    }
                }

                HStack(spacing: 20) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("拍照", systemImage: "camera.fill")
                            .font(.title3)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("相册", systemImage: "photo.fill")
                            .font(.title3)
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("拍照识别")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onChange(of: selectedItem) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        capturedImage = image
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(image: $capturedImage)
            }
            .sheet(isPresented: $showOCRResult) {
                if let image = capturedImage {
                    OCRResultView(image: image)
                }
            }
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
