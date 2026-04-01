import Foundation
import AppKit
import CoreImage
import CoreGraphics
import Vision

/// 图片主体提取服务（背景移除）
class xykt {
    static let shared = xykt()
    
    private init() {}
    private let ciContext = CIContext(options: nil)
    
    /// 检查 Apple Vision 主体提取是否可用
    func isVisionAvailable() -> Bool {
        // 检查 macOS 版本（Vision 主体提取需要 macOS 14.0+）
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        guard osVersion.majorVersion >= 14 else {
            return false
        }
        
        // 验证 Vision 框架可用性
        // VNGenerateForegroundInstanceMaskRequest 在 macOS 14.0+ 可用
        return true
    }
    
    /// 从图片中提取主体并保存到输出路径
    /// - Parameters:
    ///   - inputPath: 输入图片路径
    ///   - outputPath: 输出图片路径，若为 nil 则使用输入路径
    ///   - backgroundColor: 背景颜色，格式为 "R,G,B"（0-255），若为 nil 则保持透明
    func extractSubject(from inputPath: String, to outputPath: String? = nil, backgroundColor: String? = nil) throws {
        // 检查 Vision 是否可用
        guard isVisionAvailable() else {
            throw ExtractionError.visionNotAvailable
        }
        
        let inputURL = URL(fileURLWithPath: inputPath)
        
        // 确定输出路径
        let finalOutputPath: String
        if let outputPath = outputPath {
            finalOutputPath = outputPath
        } else {
            // 默认输出路径：在原文件名后添加 "_out"
            let inputWithoutExt = inputURL.deletingPathExtension().path
            finalOutputPath = "\(inputWithoutExt)_out.png"
        }
        
        let outputURL = URL(fileURLWithPath: finalOutputPath)
        
        // 检查输入是否为有效图片
        guard isSupportedImageFormat(inputURL) else {
            throw ExtractionError.invalidImage
        }
        
        guard let inputImage = NSImage(contentsOf: inputURL) else {
            throw ExtractionError.invalidImage
        }
        
        guard let cgImage = inputImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ExtractionError.invalidImage
        }
        
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        
        try handler.perform([request])
        
        guard let result = request.results?.first else {
            throw ExtractionError.backgroundRemovalFailed
        }
        
        let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        
        let output = try applyMask(mask, to: cgImage, backgroundColor: backgroundColor)
        
        let processedImage = NSImage(cgImage: output, size: inputImage.size)
        
        // 保存到输出路径
        guard let pngData = processedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: pngData),
              let finalData = bitmap.representation(using: .png, properties: [:]) else {
            throw ExtractionError.saveFailed
        }
        
        try finalData.write(to: outputURL)
    }
    
    /// 批量处理文件夹中的所有图片并保存到输出文件夹
    /// - Parameters:
    ///   - inputFolderPath: 输入文件夹路径
    ///   - outputFolderPath: 输出文件夹路径，若为 nil 则使用输入文件夹
    ///   - backgroundColor: 背景颜色，格式为 "R,G,B"（0-255），若为 nil 则保持透明
    func extractSubjects(fromFolder inputFolderPath: String, toFolder outputFolderPath: String? = nil, backgroundColor: String? = nil) throws {
        // 检查 Vision 是否可用
        guard isVisionAvailable() else {
            throw ExtractionError.visionNotAvailable
        }
        
        let inputFolderURL = URL(fileURLWithPath: inputFolderPath)
        
        // 确定输出文件夹路径
        let finalOutputFolderURL: URL
        if let outputFolderPath = outputFolderPath {
            finalOutputFolderURL = URL(fileURLWithPath: outputFolderPath)
            // 创建输出文件夹（如果不存在）
            try FileManager.default.createDirectory(at: finalOutputFolderURL, withIntermediateDirectories: true, attributes: nil)
        } else {
            finalOutputFolderURL = inputFolderURL
        }
        
        // 获取输入文件夹中的所有图片文件
        let fileManager = FileManager.default
        guard let fileURLs = try? fileManager.contentsOfDirectory(at: inputFolderURL, includingPropertiesForKeys: nil, options: []) else {
            throw ExtractionError.invalidArguments
        }
        
        // 处理每个图片文件
        for fileURL in fileURLs {
            // 跳过非图片文件
            guard isSupportedImageFormat(fileURL) else {
                continue
            }
            
            // 确定输出文件路径
            let fileName = fileURL.lastPathComponent
            let outputFileName = "\(fileURL.deletingPathExtension().lastPathComponent)_out.png"
            let outputFileURL = finalOutputFolderURL.appendingPathComponent(outputFileName)
            
            // 处理图片
            try extractSubject(from: fileURL.path, to: outputFileURL.path, backgroundColor: backgroundColor)
            print("处理完成: \(fileName)")
        }
    }
    
    /// 检查文件是否为支持的图片格式
    private func isSupportedImageFormat(_ fileURL: URL) -> Bool {
        let supportedExtensions = ["jpg", "jpeg", "png", "gif", "tiff", "bmp"]
        let fileExtension = fileURL.pathExtension.lowercased()
        return supportedExtensions.contains(fileExtension)
    }
    
    /// 应用蒙版到图片
    /// - Parameters:
    ///   - mask: 蒙版像素缓冲区
    ///   - image: 原始图片
    ///   - backgroundColor: 背景颜色，格式为 "R,G,B"（0-255），若为 nil 则保持透明
    private func applyMask(_ mask: CVPixelBuffer, to image: CGImage, backgroundColor: String?) throws -> CGImage {
        let ciImage = CIImage(cgImage: image)
        let maskImage = CIImage(cvPixelBuffer: mask)
        
        if let bgColor = backgroundColor {
            // 解析背景颜色
            let components = bgColor.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard components.count == 3 else {
                throw ExtractionError.invalidArguments
            }
            
            let r = CGFloat(components[0]) / 255.0
            let g = CGFloat(components[1]) / 255.0
            let b = CGFloat(components[2]) / 255.0
            
            // 创建背景颜色
            let bgColorImage = CIImage(color: CIColor(red: r, green: g, blue: b, alpha: 1.0))
                .cropped(to: ciImage.extent)
            
            // 创建带透明度的前景
            let foregroundWithMask = CIFilter(name: "CIBlendWithMask")!
            foregroundWithMask.setValue(ciImage, forKey: kCIInputImageKey)
            foregroundWithMask.setValue(maskImage, forKey: kCIInputMaskImageKey)
            foregroundWithMask.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
            
            // 将前景与背景混合
            let compositeFilter = CIFilter(name: "CISourceOverCompositing")!
            compositeFilter.setValue(foregroundWithMask.outputImage, forKey: kCIInputImageKey)
            compositeFilter.setValue(bgColorImage, forKey: kCIInputBackgroundImageKey)
            
            guard let output = compositeFilter.outputImage else {
                throw ExtractionError.backgroundRemovalFailed
            }
            
            let context = CIContext()
            guard let result = context.createCGImage(output, from: output.extent) else {
                throw ExtractionError.backgroundRemovalFailed
            }
            
            return result
        } else {
            // 保持透明背景
            let filter = CIFilter(name: "CIBlendWithMask")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(maskImage, forKey: kCIInputMaskImageKey)
            filter?.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
            
            guard let output = filter?.outputImage else {
                throw ExtractionError.backgroundRemovalFailed
            }
            
            let context = CIContext()
            guard let result = context.createCGImage(output, from: output.extent) else {
                throw ExtractionError.backgroundRemovalFailed
            }
            
            return result
        }
    }
}

// MARK: - 错误定义
enum ExtractionError: LocalizedError {
    case invalidImage
    case backgroundRemovalFailed
    case saveFailed
    case visionNotAvailable
    case invalidArguments
    case folderAccessFailed
    case outputDirectoryCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无效的图片格式"
        case .backgroundRemovalFailed:
            return "背景移除失败"
        case .saveFailed:
            return "保存文件失败"
        case .visionNotAvailable:
            return "需要 macOS 14.0+ 版本"
        case .invalidArguments:
            return "无效的参数"
        case .folderAccessFailed:
            return "无法访问文件夹"
        case .outputDirectoryCreationFailed:
            return "无法创建输出目录"
        }
    }
}

// MARK: - 命令行界面
if CommandLine.arguments.count >= 2 {
    let command = CommandLine.arguments[1]
    
    switch command {
    case "-c":
        // 检查 Vision 框架可用性
        let isAvailable = xykt.shared.isVisionAvailable()
        print(isAvailable ? "true" : "false")
        exit(isAvailable ? 0 : 1)
        
    case "-e":
        // 处理单个图片
        guard CommandLine.arguments.count >= 3 else {
            print("错误: 参数不足，请提供输入路径")
            exit(1)
        }
        let inputPath = CommandLine.arguments[2]
        var outputPath: String? = nil
        var backgroundColor: String? = nil
        
        // 解析可选参数
        var i = 3
        while i < CommandLine.arguments.count {
            let arg = CommandLine.arguments[i]
            if arg == "-bg" && i + 1 < CommandLine.arguments.count {
                backgroundColor = CommandLine.arguments[i + 1]
                i += 2
            } else if outputPath == nil {
                outputPath = arg
                i += 1
            } else {
                print("错误: 无效的参数")
                exit(1)
            }
        }
        
        do {
            try xykt.shared.extractSubject(from: inputPath, to: outputPath, backgroundColor: backgroundColor)
            print("处理成功")
        } catch {
            print("错误: \(error.localizedDescription)")
            exit(1)
        }
        
    case "-b":
        // 批量处理文件夹
        guard CommandLine.arguments.count >= 3 else {
            print("错误: 参数不足，请提供输入文件夹路径")
            exit(1)
        }
        let inputFolderPath = CommandLine.arguments[2]
        var outputFolderPath: String? = nil
        var backgroundColor: String? = nil
        
        // 解析可选参数
        var i = 3
        while i < CommandLine.arguments.count {
            let arg = CommandLine.arguments[i]
            if arg == "-bg" && i + 1 < CommandLine.arguments.count {
                backgroundColor = CommandLine.arguments[i + 1]
                i += 2
            } else if outputFolderPath == nil {
                outputFolderPath = arg
                i += 1
            } else {
                print("错误: 无效的参数")
                exit(1)
            }
        }
        
        do {
            try xykt.shared.extractSubjects(fromFolder: inputFolderPath, toFolder: outputFolderPath, backgroundColor: backgroundColor)
            print("批量处理完成")
        } catch {
            print("错误: \(error.localizedDescription)")
            exit(1)
        }
        
    case "-h", "--help":
        // 打印使用说明
        print("鲜艺抠图工具")
        print("用法:")
        print("  -c: 检查 Vision 框架可用性")
        print("  -e <输入路径> [输出路径] [-bg <R,G,B>]: 处理单个图片")
        print("    -bg <R,G,B>: 设置背景颜色（0-255），默认为透明")
        print("  -b <输入文件夹> [输出文件夹] [-bg <R,G,B>]: 批量处理文件夹中的图片")
        print("    -bg <R,G,B>: 设置背景颜色（0-255），默认为透明")
        print("  -h, --help: 显示此帮助信息")
        print("")
        print("示例:")
        print("  处理单个图片并保存为新文件:")
        print("    xykt -e input.jpg output.png")
        print("  处理单个图片并设置背景颜色:")
        print("    xykt -e input.jpg -bg 255,255,255")
        print("  批量处理文件夹中的图片:")
        print("    xykt -b input_folder output_folder")
        print("  批量处理并设置背景颜色:")
        print("    xykt -b input_folder -bg 255,255,255")
        exit(0)
        
    default:
        print("错误: 无效的命令")
        print("使用 -h 查看帮助信息")
        exit(1)
    }
}
