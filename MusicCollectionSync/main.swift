//
//  main.swift
//  MusicCollectionSync
//
//  Created by Benjamin Baron on 1/11/17.
//  Copyright © 2017 Einstein Times Two Software. All rights reserved.
//

// TODOs:
// 1. Add replaygain support (copy the replaygain tag if it exists, or calculate it if it doesn't)
// 2. Support more tags
// 3. Update existing tags when file exists if tags are different
// 4. Figure out the correct tag name for energy level
// 5. Add ability to remove files from output directory that don't exist in the input directory
// 6. Support more lame encoder options
// 7. Support more output formats
// 9. Don't hard code paths
// 10. Return stderr when exit code is not 0
// 11. Add ability to view LAME status output
// 12. Fix "fatal error: Could not open pipe file handles: file Foundation/NSFileHandle.swift, line 336" on linux

import Foundation

#if os(OSX)
let mediainfoPath = "/usr/local/bin/mediainfo"
let lamePath = "/usr/local/bin/lame"
let flacPath = "/usr/local/bin/flac"
#else
let mediainfoPath = "/usr/bin/mediainfo"
let lamePath = "/usr/bin/lame"
let flacPath = "/usr/bin/flac"
#endif

let fileManager = FileManager.default
let operationQueue = OperationQueue()
operationQueue.maxConcurrentOperationCount = 8

func outPipeShell(arguments: [String]) -> (Pipe, Pipe) {
    #if os(OSX)
        let task = Process()
    #else
        let task = Task()
    #endif
    task.launchPath = "/usr/bin/env"
    task.arguments = arguments
    
    let outPipe = Pipe()
    let errPipe = Pipe()
    task.standardInput = Pipe()
    task.standardOutput = outPipe
    task.standardError = errPipe
    task.launch()
    
    return (outPipe, errPipe)
}

func shell(inPipe: Pipe = Pipe(), arguments: [String]) -> (String?, String?, Int32)
{
    #if os(OSX)
        let task = Process()
    #else
        let task = Task()
    #endif
    task.launchPath = "/usr/bin/env"
    task.arguments = arguments
    
    let outPipe = Pipe()
    let errPipe = Pipe()
    task.standardInput = inPipe
    task.standardOutput = outPipe
    task.standardError = errPipe
    task.launch()
    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    
    let outputString = String(data: outData, encoding: .utf8)
    let errorString = errData.count > 0 ? String(data: errData, encoding: .utf8) : nil
    return (outputString, errorString, task.terminationStatus)
}

extension String {
    var escapedQuotes: String {
        return self.replacingOccurrences(of: "\"", with: "\"\"")
    }
}

enum FileExtension: String {
    case aiff = "aiff"
    case aif  = "aif"
    case wave = "wave"
    case wav  = "wav"
    case flac = "flac"
    case m4a  = "m4a"
    case mp4  = "mp4"
    case mp3  = "mp3"
    case ogg  = "ogg"
    
    case tmp  = "tmp"
    
    var isLossless: Bool {
        return self == .aiff || self == .aif || self == .wave || self == .wav || self == .flac
    }
}

enum FormatType: String {
    case aiff = "AIFF"
    case wav  = "Wave"
    case flac = "FLAC"
    case mp3  = "MPEG Audio"
    case m4a  = "MPEG-4"
    case ogg  = "Ogg"
    
    case unsupported = "unsupported"
}

enum ImageMimeType: String {
    case jpeg = "image/jpeg"
    case png  = "image/png"
    case gif  = "image/gif"
}

enum TagType: String {
    case title        = "Title"
    case trackName    = "Track name" // See if this is necessary
    case artist       = "Performer"
    case album        = "Album"
    case track        = "Track name/Position"
    case trackTotal   = "Track name/Total"
    case genre        = "Genre"
    case year         = "Recorded date"
    case comment      = "Comment"
    case coverMime    = "Cover MIME"
    case coverData    = "Cover_Data"
    case format       = "Format"
    case bpm          = "BPM"
    case rating       = "Rating"
    case energyLevel  = "EnergyLevel"
    case energyLevel2 = "energylevel"
    case initialKey   = "Initial key"
    case initialKey2  = "initialkey"
}

struct Tags {
    let format: FormatType
    
    let title: String?
    let artist: String?
    let album: String?
    let year: Int?
    let comment: String?
    let track: Int?
    let trackTotal: Int?
    let genre: String?
    let coverData: Data?
    let coverMimeType: ImageMimeType?
    let userTags: [TagType: String]?
    
    init?(filePath: String) {
        let arguments = [mediainfoPath, "-f", filePath]
        if let mediainfoOutput = shell(arguments: arguments).0 {
            self.init(mediainfoOutput: mediainfoOutput)
        } else {
            return nil
        }
    }

    init(mediainfoOutput: String) {
        let lines = mediainfoOutput.components(separatedBy: "\n")
        var tagDict = [TagType: String]()
        for line in lines {
            let components = line.components(separatedBy: ":")
            if components.count > 1 {
                var tagString = components[0].trimmingCharacters(in: .whitespaces)
                #if !os(OSX)
                    // Fix for trimmingCharacters bug in Linux where it removes trailing r's
                    tagString = (tagString == "Performe" ? "Performer" : tagString)
                #endif
                if let tag = TagType(rawValue: tagString) {
                    var value = components[1]
                    if components.count > 2 {
                        for i in 2...components.count-1 {
                            value += ":\(components[i])"
                        }
                    }
                    value = value.trimmingCharacters(in: .whitespaces)
                    
                    if value.characters.count > 0 && !tagDict.keys.contains(tag) {
                        tagDict[tag] = value
                    }
                }
            }
        }
        
        // Log if title and trackName are different, I don't think they ever are
        if let title = tagDict[.title], let trackName = tagDict[.trackName], title != trackName {
            print("WARNING: Title and track name don't match")
            print("title: \(title)")
            print("trackName: \(trackName)")
        }
        
        let formatString = tagDict[.format] ?? ""
        self.format = FormatType(rawValue: formatString) ?? .unsupported
        self.title = tagDict[.title] ?? tagDict[.trackName]
        self.artist = tagDict[.artist]
        self.album = tagDict[.album]
        if let yearString = tagDict[.year] {
            self.year = Int(yearString)
        } else {
            self.year = nil
        }
        self.comment = tagDict[.comment]
        if let trackString = tagDict[.track] {
            self.track = Int(trackString)
        } else {
            self.track = nil
        }
        if let trackTotalString = tagDict[.trackTotal] {
            if let trackTotal = Int(trackTotalString) {
                self.trackTotal = trackTotal
            } else {
                // Sometimes it's in this format 1 / 16
                let components = trackTotalString.components(separatedBy: "/")
                if components.count > 0 {
                    self.trackTotal = Int(components[0].trimmingCharacters(in: .whitespaces))
                } else {
                    self.trackTotal = nil
                }
            }
        } else {
            self.trackTotal = nil
        }
        self.genre = tagDict[.genre]
        if let coverDataString = tagDict[.coverData] {
            self.coverData = Data(base64Encoded: coverDataString)
        } else {
            self.coverData = nil
        }
        let coverMimeString = tagDict[.coverMime] ?? ""
        self.coverMimeType = ImageMimeType(rawValue: coverMimeString)

        var userTags = [TagType: String]()
        if let bpmString = tagDict[.bpm] {
            if let bpmInt = Int(bpmString) {
                userTags[.bpm] = "\(bpmInt)"
            } else if let bpmFloat = Float(bpmString) {
                userTags[.bpm] = "\(bpmFloat)"
            }
        }
        if let rating = tagDict[.rating] {
            userTags[.rating] = rating
        }
        if let energyLevel = tagDict[.energyLevel] ?? tagDict[.energyLevel2] {
            userTags[.energyLevel] = energyLevel
        }
        if let initialKey = tagDict[.initialKey] ?? tagDict[.initialKey2] {
            userTags[.initialKey] = initialKey
        }
        self.userTags = userTags.count > 0 ? userTags : nil
    }
}

func lameTagOptions(fromTags tags: Tags?, coverArtPath: String?) -> [String] {
    var arguments = [String]()
    if let tags = tags {
        if let title = tags.title {
            arguments.append("--tt")
            arguments.append(title)
        }
        if let artist = tags.artist {
            arguments.append("--ta")
            arguments.append(artist)
        }
        if let album = tags.album {
            arguments.append("--tl")
            arguments.append(album)
        }
        if let year = tags.year {
            arguments.append("--ty")
            arguments.append("\(year)")
        }
        if let comment = tags.comment {
            arguments.append("--tc")
            arguments.append(comment)
        }
        if let track = tags.track {
            var argument = "\(track)"
            if let trackTotal = tags.trackTotal {
                argument += "/\(trackTotal)"
            }
            
            arguments.append("--tn")
            arguments.append(argument)
        }
        if let genre = tags.genre {
            arguments.append("--tg")
            arguments.append(genre)
        }
        if let coverArtPath = coverArtPath {
            arguments.append("--ti")
            arguments.append(coverArtPath)
        }
        
        if let userTags = tags.userTags {
            for (tag, value) in userTags {
                switch tag {
                case .bpm:
                    arguments.append("--tv")
                    arguments.append("TBPM=\(value)")
                case .initialKey:
                    arguments.append("--tv")
                    arguments.append("TKEY=\(value)")
                case .rating:
                    arguments.append("--tv")
                    arguments.append("POPM=\(value)")
                default:
                    break
                }
            }
        }
    }
    
    return arguments
}

func lameCommand(input: String, output: String, tags: Tags?, coverArtPath: String?) -> [String] {
    let tagOptions = lameTagOptions(fromTags: tags, coverArtPath: coverArtPath)
    
    var arguments = [String]()
    arguments.append(lamePath)
    arguments.append("--silent")
    arguments.append("-h")
    arguments.append("--add-id3v2")
    arguments.append("--noreplaygain")
    arguments.append("-V")
    arguments.append("0")
    arguments.append(contentsOf: tagOptions)
    arguments.append(input)
    arguments.append(output)
    return arguments
}

func fullPath(directory: String, fileName: String) -> String {
    return "\(directory)/\(fileName)"
}

func outputFileName(forFileName fileName: String) -> String {
    let url = NSURL(fileURLWithPath: fileName)
    if let pathExtension = url.pathExtension, let fileExtension = FileExtension(rawValue: pathExtension), fileExtension.isLossless {
        if let nameWithoutExtension = url.deletingPathExtension?.relativeString.removingPercentEncoding {
            return nameWithoutExtension + "." + FileExtension.mp3.rawValue
        }
    }
    
    return fileName
}

func tempOutputFileName(forFileName fileName: String) -> String {
    return outputFileName(forFileName: fileName) + "." + FileExtension.tmp.rawValue
}

func convertUncompressed(name: String, fileExtension: FileExtension, inDirectory: String, outDirectory: String) {
    let fullInPath = fullPath(directory: inDirectory, fileName: name)
    let fullTempOutPath = fullPath(directory: outDirectory, fileName: tempOutputFileName(forFileName: name))
    let fullOutPath = fullPath(directory: outDirectory, fileName: outputFileName(forFileName: name))
    let tags = Tags(filePath: fullInPath)
    var coverArtExists = false
    var coverArtPath: String?
    if let coverData = tags?.coverData, tags?.coverMimeType != nil {
        let tempArtUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name.escapedQuotes).art")
        coverArtPath = tempArtUrl.path
        do {
            try coverData.write(to: tempArtUrl)
            coverArtExists = true
        } catch {
            print("Error writing cover art to disk at path: \(coverArtPath!): error: \(error)")
        }
    }
    
    var errorString: String? = nil
    if fileExtension == .flac {
        let flacArguments = [flacPath, "-cd", fullInPath]
        let lameArguments = lameCommand(input: "-", output: fullTempOutPath, tags: tags, coverArtPath: coverArtPath)
        let flacOut = outPipeShell(arguments: flacArguments)
        let lameOut = shell(inPipe: flacOut.0, arguments: lameArguments)
        errorString = lameOut.1
        
    } else {
        let lameArguments = lameCommand(input: fullInPath, output: fullTempOutPath, tags: tags, coverArtPath: coverArtPath)
        let lameOut = shell(arguments: lameArguments)
        errorString = lameOut.1
    }
    
    if let errorString = errorString {
        print("Error converting file at path: \(fullInPath) error: \(errorString)")
    } else {
        do {
            try fileManager.moveItem(atPath: fullTempOutPath, toPath: fullOutPath)
        } catch {
            print("Error moving temp file at path: \(fullTempOutPath) to path: \(fullOutPath) error: \(error)")
        }
    }
    
    if coverArtExists, let coverArtPath = coverArtPath {
        do {
            try fileManager.removeItem(atPath: coverArtPath)
        } catch {
            print("Error removing cover art at path: \(coverArtPath) error: \(error)")
        }
    }
}

func convertFile(name: String, fileExtension: FileExtension, inDirectory: String, outDirectory: String) {
    do {
        let fullInPath = fullPath(directory: inDirectory, fileName: name)
        let fullTempOutPath = fullPath(directory: outDirectory, fileName: tempOutputFileName(forFileName: name))
        let fullOutPath = fullPath(directory: outDirectory, fileName: outputFileName(forFileName: name))
        if fileManager.fileExists(atPath: fullOutPath) {
            print("skipping \(name) because it already exists")
        } else if fileExtension.isLossless {
            print("converting \(name) from: \(inDirectory) to: \(outDirectory)")
            convertUncompressed(name: name, fileExtension: fileExtension, inDirectory: inDirectory, outDirectory: outDirectory)
        } else {
            print("copying \(name) from: \(inDirectory) to: \(outDirectory)")
            #if os(OSX)
                try fileManager.copyItem(atPath: fullInPath, toPath: fullTempOutPath)
                try fileManager.moveItem(atPath: fullTempOutPath, toPath: fullOutPath)
            #else
                _ = shell(arguments: ["cp", fullInPath, fullOutPath])
            #endif
        }
    } catch {
        print("convertFile error: \(error)")
    }
}

func convertFiles(inDirectory: String, outDirectory: String) {
    var directories = [String]()
    do {
        if !fileManager.fileExists(atPath: outDirectory) {
            try fileManager.createDirectory(atPath: outDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        
        let fileNames = try fileManager.contentsOfDirectory(atPath: inDirectory)
        for fileName in fileNames {
            if fileName == ".DS_Store" {
                continue
            }
            
            let fullInPath = fullPath(directory: inDirectory, fileName: fileName)
            let fullInUrl = URL(fileURLWithPath: fullInPath)
            if let fileExtension = FileExtension(rawValue: fullInUrl.pathExtension) {
                if fileExtension == .tmp {
                    continue
                } else {
                    operationQueue.addOperation{
                        convertFile(name: fileName, fileExtension: fileExtension, inDirectory: inDirectory, outDirectory: outDirectory)
                    }
                }
            } else {
                var isDirectoryOutput: ObjCBool = false
                _ = fileManager.fileExists(atPath: fullInPath, isDirectory: &isDirectoryOutput)
                #if os(OSX)
                    let isDirectory = isDirectoryOutput.boolValue
                #else
                    let isDirectory = isDirectoryOutput
                #endif
                if isDirectory {
                    directories.append(fileName)
                }
            }
        }
    } catch {
        print("convertFiles error reading contents of directory: \(error)")
    }
    
    for directory in directories {
        let fullInDirectoryPath = fullPath(directory: inDirectory, fileName: directory)
        let fullOutDirectoryPath = fullPath(directory: outDirectory, fileName: directory)
        convertFiles(inDirectory: fullInDirectoryPath, outDirectory: fullOutDirectoryPath)
    }
}

func removeTempFiles(outDirectory: String) {
    let output = shell(arguments: ["find", outDirectory, "-name", "*.\(FileExtension.tmp.rawValue)", "-type", "f", "-delete"])
    print(output.0!)
}

func main() {
    let arguments = CommandLine.arguments
    //print("arguments: \(arguments)")
    if arguments.count < 3 {
        print("This tool recursively walks a folder of media files and syncs it to another folder as mp3s")
        print("It converts any lossless files to mp3 and just copies any lossy files")
        print("Usage: \(arguments[0]) inputFolderPath outputFolderPath")
    } else {
        removeTempFiles(outDirectory: CommandLine.arguments[2])
        convertFiles(inDirectory: arguments[1], outDirectory: arguments[2])
    }
    
    operationQueue.waitUntilAllOperationsAreFinished()
}

main()
