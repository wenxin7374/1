import Photos
import UIKit

final class PhotoSaveManager {
    static let shared = PhotoSaveManager()

    enum SaveError: LocalizedError {
        case noPermission
        case failed(Error?)

        var errorDescription: String? {
            switch self {
            case .noPermission:
                return "没有相册添加权限，请在系统设置中开启。"
            case .failed(let error):
                return error?.localizedDescription ?? "写入相册失败"
            }
        }
    }

    /// 使用 addOnly 权限写入系统相册；异步执行，不阻塞取景预览。
    func save(_ image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(.failure(SaveError.noPermission)) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        completion(.success(()))
                    } else {
                        completion(.failure(SaveError.failed(error)))
                    }
                }
            }
        }
    }
}
