import SwiftUI
import FirebaseStorage
import FirebaseCore
import FirebaseAuth

class StorageService: ObservableObject {
    private var storage: Storage
    private let bucketURL = "gs://bumpin-19cf2.firebasestorage.app"
    
    init() {
        self.storage = Storage.storage(url: bucketURL)
        print("Initialized Firebase Storage with URL: \(bucketURL)")
        
        let rootRef = storage.reference()
        print("Root reference details:")
        print("- Bucket: \(rootRef.bucket)")
        print("- Full path: \(rootRef.fullPath)")
        print("- Storage URL: \(rootRef.description)")
    }
    
    func uploadProfileImage(_ image: UIImage, userId: String) async throws -> String {
        // Verify user is authenticated
        let auth = Auth.auth()
        print("Checking authentication state...")
        if let currentUser = auth.currentUser {
            print("User is authenticated:")
            print("- UID: \(currentUser.uid)")
            print("- Email: \(currentUser.email ?? "No email")")
            print("- Is Anonymous: \(currentUser.isAnonymous)")
            print("- Provider ID: \(currentUser.providerID)")
        } else {
            print("No user is currently signed in")
            throw NSError(domain: "StorageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User is not authenticated"])
        }
        
        guard let currentUser = auth.currentUser else {
            throw NSError(domain: "StorageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User is not authenticated"])
        }
        
        guard currentUser.uid == userId else {
            print("User ID mismatch:")
            print("- Current user ID: \(currentUser.uid)")
            print("- Requested user ID: \(userId)")
            throw NSError(domain: "StorageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User ID mismatch"])
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare image for upload"])
        }
        
        print("Image data size: \(imageData.count) bytes")
        
        // Create a unique filename with timestamp to avoid conflicts
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "\(userId)_\(timestamp).jpg"
        
        // Create the storage reference directly with the full path
        let fullPath = "profile_images/\(filename)"
        let imageRef = storage.reference(withPath: fullPath)
        
        print("Storage reference details:")
        print("- Storage URL: \(bucketURL)")
        print("- Full path: \(imageRef.fullPath)")
        print("- Name: \(imageRef.name)")
        print("- User ID: \(userId)")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        return try await withCheckedThrowingContinuation { continuation in
            print("Starting upload task...")
            let uploadTask = imageRef.putData(imageData, metadata: metadata) { metadata, error in
                if let error = error as? NSError {
                    print("Upload failed with error:")
                    print("- Domain: \(error.domain)")
                    print("- Code: \(error.code)")
                    print("- Description: \(error.localizedDescription)")
                    print("- Error Info: \(error.userInfo)")
                    continuation.resume(throwing: error)
                    return
                }
                
                print("Upload succeeded, getting download URL...")
                // Get download URL after successful upload
                imageRef.downloadURL { url, error in
                    if let error = error {
                        print("Failed to get download URL: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let downloadURL = url else {
                        let error = NSError(domain: "StorageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"])
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    print("Upload completed successfully. Download URL: \(downloadURL.absoluteString)")
                    continuation.resume(returning: downloadURL.absoluteString)
                }
            }
            
            uploadTask.observe(.progress) { snapshot in
                let percentComplete = Double(snapshot.progress?.completedUnitCount ?? 0) / Double(snapshot.progress?.totalUnitCount ?? 1) * 100
                print("Upload progress: \(Int(percentComplete))%")
            }
        }
    }
    
    func loadProfileImage(from urlString: String) async throws -> UIImage {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image from data"])
            }
            return image
        } catch {
            throw NSError(
                domain: "",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load image: \(error.localizedDescription)"]
            )
        }
    }
    
    func deleteProfileImage(urlString: String) async throws {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image URL"])
        }
        
        // Get the last path component as the filename
        guard let filename = url.pathComponents.last else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image path"])
        }
        
        let imageRef = storage.reference().child("profile_images").child(filename)
        
        do {
            try await imageRef.delete()
        } catch {
            throw NSError(
                domain: "",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to delete image: \(error.localizedDescription)"]
            )
        }
    }
} 