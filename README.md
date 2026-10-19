# SidecarCinema v0.1

A small native macOS app for showing one local video as a left/right panorama across a Mac display and a Sidecar iPad.

## How synchronization works

There is only one `AVPlayer` and one playback clock. Its single `AVPlayerItemVideoOutput` supplies decoded frames; each new frame is cropped into left and right display viewports and sent to two borderless windows. AVPlayer sends the video's audio through the Mac's normal audio output once. The two displays therefore receive crops from the same decoded frame rather than running separate players.

The renderer currently samples at 30 frames per second. Both panels update from that same sample. This is synchronized playback, though not a guarantee of 60 Hz panel refresh or frame-perfect hardware scan-out.

## Build and run

1. Connect the iPad with Sidecar. In macOS, arrange displays with the Mac on the left and iPad on the right if that matches the physical setup.
2. Open `SidecarCinema.xcodeproj` in Xcode 15 or later.
3. Select the **SidecarCinema** scheme and **My Mac**, then Build and Run. The project targets macOS 13 or later and Apple Silicon.
4. In the app, choose a video with **Open Video…** or drop a movie file onto the window.
5. Assign the Mac display to **Left screen** and Sidecar to **Right screen**. Use **Refresh** after connecting or disconnecting a display.
6. Adjust **Bezel / gap** in millimeters. Start at 0, then increase it until objects crossing the seam line up across the physical gap.
7. Choose **Start Dual Screen**. Press Space to pause/resume, Left/Right to seek 10 seconds, or Esc to close the two video windows.

Display assignment and gap calibration are saved between launches. The image uses the measured physical display dimensions where macOS provides them; it falls back to logical screen size otherwise. If the displays have different physical heights, the shorter screen shows the centered vertical portion of the shared canvas.

## MVP boundaries

- Local movie files supported by AVFoundation; the file picker accepts movie types, not only MP4 containers.
- One active video and two connected displays. No library, playlist, subtitles UI, or independent screen controls.
- The complete video frame is scaled proportionally to fit the combined display canvas. No source edges are cropped; unused canvas area is filled with black bars.
- The gap slider compensates by skipping image content under the physical gap. It does not correct for tilted screens, different vertical positions, color matching, or display latency.
- If Sidecar is disconnected, exit Dual Screen, reconnect it, refresh the display list, and start again.

## Build verification

The source and Xcode project are included. This project was prepared in an environment with Apple Swift command line tools but without the full Xcode installation/SDK selected, so an Xcode build could not be run here. Open the project in Xcode on the target Mac to build and exercise the two-display path.
