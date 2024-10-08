import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

let maxDimension = 1024

// Get the folder path from the command line
let arguments = CommandLine.arguments
guard arguments.count == 2 else {
	print("Syntax: ImageResizer <folder>")
	exit(1)
}

// Create the output folder
let inputFolderURL = URL(fileURLWithPath: arguments[1])
let outputFolderURL = inputFolderURL.appendingPathComponent("Resized")
try? FileManager.default.createDirectory(at: outputFolderURL, withIntermediateDirectories: false, attributes: nil)

// Read the list of input files
var fileURLs: [URL]
do {
	fileURLs = try FileManager.default.contentsOfDirectory(at: inputFolderURL, includingPropertiesForKeys: nil)
} catch {
	print("Error reading contents of folder: \(error.localizedDescription)")
	exit(1)
}

for fileURL in fileURLs {
	// Skip non-images
	guard let fileUTI = UTType(filenameExtension: fileURL.pathExtension), fileUTI.conforms(to: .image) else { continue }

	// Open the image
	guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("Failed to load image"); exit(1) }

	// Calculate the new size
	let aspectRatio = CGFloat(image.width) / CGFloat(image.height)
	let newSize: CGSize = image.width > image.height ?
		CGSize(width: maxDimension, height: Int(CGFloat(maxDimension) / aspectRatio)) :
		CGSize(width: Int(CGFloat(maxDimension) * aspectRatio), height: maxDimension)

	guard let context = CGContext(
		data: nil,
		width: Int(newSize.width),
		height: Int(newSize.height),
		bitsPerComponent: image.bitsPerComponent,
		bytesPerRow: 0,
		space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
		bitmapInfo: image.bitmapInfo.rawValue)
	else { print("Failed to create graphics context"); exit(1) }
	context.interpolationQuality = .high

	// Read the image orientation metadata
	let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as! [CFString: Any]
	let orientation = CGImagePropertyOrientation(rawValue: (properties[kCGImagePropertyOrientation] as? UInt32) ?? 0)

	// Transform based on original image orientation metadata.
	var transform = CGAffineTransform.identity
	switch orientation {
	case .upMirrored: transform = transform.translatedBy(x: newSize.width, y: 0).scaledBy(x: -1, y: 1)
	case .down: transform = transform.translatedBy(x: newSize.width, y: newSize.height).rotated(by: .pi)
	case .downMirrored: transform = transform.translatedBy(x: 0, y: newSize.height).scaledBy(x: 1, y: -1)
	case .left: transform = transform.translatedBy(x: 0, y: newSize.height).rotated(by: -.pi / 2)
	case .leftMirrored: transform = transform.translatedBy(x: newSize.width, y: newSize.height).scaledBy(x: -1, y: 1).rotated(by: -.pi / 2)
	case .right: transform = transform.translatedBy(x: newSize.width, y: 0).rotated(by: .pi / 2)
	case .rightMirrored: transform = transform.scaledBy(x: -1, y: 1).rotated(by: .pi / 2)
	default: break
	}
	context.concatenate(transform)

	// Draw the image
	context.draw(image, in: CGRect(origin: .zero, size: newSize))
	guard let resizedImage = context.makeImage() else { print("Failed to create resized image"); exit(1) }

	// Determine the output format and file extension
	let losslessTypes: [String] = [UTType.png, UTType.tiff, UTType.gif].map { $0.identifier }
	guard let type = CGImageSourceGetType(source) else { print("Failed to get image type"); exit(1) }
	let outputType = losslessTypes.contains(type as String) ? UTType.png : UTType.jpeg
	let outputPath = outputFolderURL.appendingPathComponent(fileURL.lastPathComponent).deletingPathExtension().appendingPathExtension(for: outputType)

	// Save the image
	guard let destination = CGImageDestinationCreateWithURL(outputPath as CFURL, outputType.identifier as CFString, 1, nil) else { print("Failed to create image destination"); exit(1) }
	CGImageDestinationAddImage(destination, resizedImage, nil)
	guard CGImageDestinationFinalize(destination) else { print("Failed to save image"); exit(1) }
}
