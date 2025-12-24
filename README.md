   git clone <https://github.com/andycabindol/Chirper.git>
   cd Chirper: Machine learning inference engine
- **AVFoundation**: Audio processing and playback
- **SwiftUI**: User interface framework

## Technical Details

### BirdNET Integration

- Uses BirdNET v2.4 TensorFlow Lite model
- Processes audio in 3-second windows
- Supports 30 languages for species labels
- Confidence scores range from 0.0 to 1.0

### Audio Processing

- Automatic format detection and decoding
- Resampling to 48kHz (BirdNET requirement)
- Segment extraction with configurable padding
- Trim support with minimum duration enforcement

### Performance

- Processing runs asynchronously
- Progress tracking for long recordings
- Efficient memory management for large files
- Background processing support

## Configuration

### Confidence Threshold

Default: **75%** (0.75)

Adjust via the filter sheet:
- Tap filter icon in results view
- Use slider to set threshold (1-100%)
- Apply to filter species below threshold

### Export Settings

- **Per Species**: Combines all clips for a species into one file
- **Per Call**: Exports each clip as a separate file
- Files are saved with species names and timestamps

## Troubleshooting

### Code Signing Errors

1. Ensure your development team is selected in Xcode
2. Check "Automatically manage signing" is enabled
3. Clean build folder (⇧⌘K)
4. Delete DerivedData if issues persist

### Build Errors

1. Run `pod install` to ensure dependencies are up to date
2. Clean build folder (⇧⌘K)
3. Restart Xcode
4. Check disk space (requires free space for builds)

### Audio Playback Issues

- Ensure device volume is up
- Check that audio session is properly configured
- Verify file format is supported

## Development

### Adding New Features

The app uses a clean MVVM architecture:
- **Views**: SwiftUI views in separate files
- **ViewModels**: `AppViewModel` manages app state
- **Services**: Separate service classes for specific functionality

### Testing

- Mock implementation available for testing without TensorFlow Lite
- Set `usingMock` flag in `AppViewModel` for development

## Credits

- **BirdNET**: Bird sound identification model by the K. Lisa Yang Center for Conservation Bioacoustics
- **TensorFlow Lite**: Machine learning framework by Google
- **Bird Images**: Fetched from external APIs (see `BirdImageService.swift`)

## Author

Created by Andy Cabindol

---

**Note**: This app requires an active internet connection for bird image loading. Audio processing and bird detection work offline using the embedded TensorFlow Lite model.