import Foundation
import Testing

@testable import SunshotCore

@Suite("Video export plan")
struct VideoExportPlanTests {
    @Test("[S13-AC9] resolution sets the shorter side; sides are even and at most 4096 px")
    func resolution() {
        let landscape = PixelSize(width: 1128, height: 728)
        for resolution in VideoResolution.allCases {
            let plan = VideoExportPlan.make(
                canvasSize: landscape, options: VideoExportOptions(resolution: resolution), duration: 2,
                transparent: false)
            #expect(abs(plan.height - resolution.shortSide) <= 1, "\(resolution)")
            #expect(plan.width % 2 == 0 && plan.height % 2 == 0)
            #expect(abs(Double(plan.width) / Double(plan.height) - 1128.0 / 728) < 0.01)
        }
        let odd = VideoExportPlan.make(
            canvasSize: PixelSize(width: 333, height: 333), options: VideoExportOptions(resolution: .p720),
            duration: 1, transparent: false)
        #expect(odd.width == 720 && odd.height == 720)
        let tall = VideoExportPlan.make(
            canvasSize: PixelSize(width: 400, height: 2000), options: VideoExportOptions(resolution: .twoK),
            duration: 1, transparent: false)
        #expect(tall.height == 4096 && tall.width == 818 && tall.width % 2 == 0)
        #expect(VideoResolution.allCases.map(\.label) == ["720p", "HD", "2K"])
    }

    @Test("[S13-AC9] frame count, timing and encoding follow the options and the backdrop")
    func framesAndEncoding() {
        let size = PixelSize(width: 640, height: 360)
        let plan30 = VideoExportPlan.make(
            canvasSize: size, options: VideoExportOptions(frameRate: .fps30), duration: 1.01, transparent: false)
        #expect(plan30.frameCount == 30 && plan30.fps == 30 && plan30.encoding == .h264)
        #expect(plan30.encoding.fileExtension == "mp4" && plan30.encoding.typeIdentifier == "public.mpeg-4")
        #expect(abs(plan30.duration - 1) < 1e-9 && abs(plan30.time(ofFrame: 15) - 0.5) < 1e-9)
        let plan60 = VideoExportPlan.make(
            canvasSize: size, options: VideoExportOptions(frameRate: .fps60, codec: .hevc), duration: 2,
            transparent: false)
        #expect(plan60.frameCount == 120 && plan60.encoding == .hevc && !plan60.encoding.hasAlpha)
        let alpha = VideoExportPlan.make(
            canvasSize: size, options: VideoExportOptions(codec: .h264), duration: 0, transparent: true)
        #expect(alpha.encoding == .hevcWithAlpha && alpha.encoding.fileExtension == "mov" && alpha.frameCount == 1)
        #expect(alpha.encoding.typeIdentifier == "com.apple.quicktime-movie")
        let capped = VideoExportPlan.make(
            canvasSize: size, options: VideoExportOptions(), duration: 500, transparent: false)
        #expect(capped.frameCount == 3600)
        #expect(VideoFrameRate.allCases.map(\.label) == ["30 fps", "60 fps"])
        #expect(VideoCodec.allCases.map(\.label) == ["H.264", "HEVC"])
    }

    @Test("[S13-AC9] a see-through backdrop is detected (None, translucent colour, backdrop opacity)")
    func transparency() {
        var project = Project()
        #expect(!project.hasTransparentBackdrop)
        project.backdrop = .none
        #expect(project.hasTransparentBackdrop)
        project.backdrop = .solid(RGBAColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        #expect(project.hasTransparentBackdrop)
        project.backdrop = .solid(RGBAColor(red: 1, green: 0, blue: 0, alpha: 1))
        project.backdropSettings.effects.adjustments.opacity = 0.4
        #expect(project.hasTransparentBackdrop)
    }

    @Test("[S13-AC19] timecodes for the transport bar and the export sheet")
    func timecodes() {
        #expect(TimecodeFormat.clock(0) == "00:00.00")
        #expect(TimecodeFormat.clock(61.5) == "01:01.50")
        #expect(TimecodeFormat.clock(-3) == "00:00.00" && TimecodeFormat.clock(.nan) == "00:00.00")
        #expect(TimecodeFormat.short(10) == "10s" && TimecodeFormat.short(2.55) == "2.6s")
        #expect(TimecodeFormat.short(.infinity) == "0s")
    }
}
