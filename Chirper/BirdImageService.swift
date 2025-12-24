import Foundation
import SwiftUI

class BirdImageService {
    static let shared = BirdImageService()
    
    private var imageCache: [String: UIImage] = [:]
    private let cacheQueue = DispatchQueue(label: "com.chirper.birdimagecache")
    
    private init() {}
    
    func getImageURL(for species: String) -> URL? {
        let (commonName, scientificName) = parseSpeciesName(species)
        
        // Try scientific name first, then common name
        let searchTerms = [scientificName, commonName].filter { !$0.isEmpty }
        
        guard let searchTerm = searchTerms.first else { return nil }
        
        // Wikipedia API: Search for the bird species
        // Format: https://en.wikipedia.org/api/rest_v1/page/summary/{title}
        let encodedTitle = searchTerm
            .replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        
        return URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encodedTitle)")
    }
    
    func fetchImage(for species: String) async -> UIImage? {
        // Check cache first
        if let cached = getCachedImage(for: species) {
            return cached
        }
        
        let (commonName, scientificName) = parseSpeciesName(species)
        let searchTerms = [scientificName, commonName].filter { !$0.isEmpty }
        
        // Try each search term until we find an image
        for searchTerm in searchTerms {
            if let image = await fetchImageFromWikipedia(searchTerm: searchTerm) {
                cacheImage(image, for: species)
                return image
            }
        }
        
        return nil
    }
    
    private func fetchImageFromWikipedia(searchTerm: String) async -> UIImage? {
        let encodedTitle = searchTerm
            .replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        
        guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encodedTitle)") else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // Check if we got a valid response
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                // Extract thumbnail URL from Wikipedia API response
                if let thumbnail = json?["thumbnail"] as? [String: Any],
                   let source = thumbnail["source"] as? String,
                   let imageURL = URL(string: source) {
                    
                    // Fetch the actual image
                    let (imageData, _) = try await URLSession.shared.data(from: imageURL)
                    if let image = UIImage(data: imageData) {
                        return image
                    }
                }
            }
        } catch {
            // Silently fail - we'll try the next search term
            return nil
        }
        
        return nil
    }
    
    private func getCachedImage(for species: String) -> UIImage? {
        cacheQueue.sync {
            return imageCache[species]
        }
    }
    
    func getCachedImageSync(for species: String) -> UIImage? {
        return cacheQueue.sync {
            return imageCache[species]
        }
    }
    
    private func cacheImage(_ image: UIImage, for species: String) {
        cacheQueue.async {
            self.imageCache[species] = image
        }
    }
    
    func preloadImages(for species: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for speciesName in species {
                group.addTask {
                    _ = await self.fetchImage(for: speciesName)
                }
            }
        }
    }
    
    private func parseSpeciesName(_ species: String) -> (commonName: String, scientificName: String) {
        if let underscoreIndex = species.lastIndex(of: "_") {
            let scientificName = String(species[..<underscoreIndex])
            let commonName = String(species[species.index(after: underscoreIndex)...])
            return (commonName, scientificName)
        } else {
            return (species, "")
        }
    }
}

struct BirdImageView: View {
    let species: String
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "bird.fill")
                    .font(.title2)
                    .foregroundColor(.black.opacity(0.7))
            }
        }
        .frame(width: 70, height: 70)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task {
            // Image should already be cached from preloading
            image = await BirdImageService.shared.fetchImage(for: species)
        }
    }
}

struct BirdImageFullWidthView: View {
    let species: String
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        Image(systemName: "bird.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.black.opacity(0.3))
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            // Image should already be cached from preloading
            image = await BirdImageService.shared.fetchImage(for: species)
        }
    }
}

