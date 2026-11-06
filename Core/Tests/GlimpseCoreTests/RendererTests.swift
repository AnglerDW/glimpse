import Foundation
import CoreGraphics
import Testing
@testable import GlimpseCore

struct RendererTests {
    @Test func cropsExactPixels() throws {
        let image = TestImage.gradient(width: 8, height: 8)
        let cropped = try #require(Renderer.crop(image, toPixelRect: CGRect(x: 2, y: 3, width: 4, height: 2)))
        #expect(cropped.width == 4)
        #expect(cropped.height == 2)
        #expect(TestImage.pixel(cropped, x: 0, y: 0) == [2, 3, 0, 255])
        #expect(TestImage.pixel(cropped, x: 3, y: 1) == [5, 4, 0, 255])
    }

    @Test func cropIsClampedToImage() throws {
        let image = TestImage.gradient(width: 8, height: 8)
        let cropped = try #require(Renderer.crop(image, toPixelRect: CGRect(x: 6, y: 6, width: 10, height: 10)))
        #expect(cropped.width == 2)
        #expect(cropped.height == 2)
    }

    @Test func cropIsIndependentOfSource() throws {
        let image = TestImage.gradient(width: 8, height: 8)
        let cropped = try #require(Renderer.crop(image, toPixelRect: CGRect(x: 1, y: 1, width: 4, height: 4)))
        #expect(cropped !== image)
        // Not a view onto the source's pixels: different data provider, tightly sized.
        #expect(cropped.dataProvider !== image.dataProvider)
        #expect((cropped.dataProvider?.data as Data?)?.count == cropped.bytesPerRow * cropped.height)
        #expect(cropped.colorSpace?.name == image.colorSpace?.name)
        #expect(TestImage.pixel(cropped, x: 3, y: 3) == [4, 4, 0, 255])
    }

    @Test func emptyCropReturnsNil() {
        let image = TestImage.gradient(width: 8, height: 8)
        #expect(Renderer.crop(image, toPixelRect: CGRect(x: 20, y: 20, width: 5, height: 5)) == nil)
    }

    @Test func fractionalPixelRectIsExpandedToIntegral() throws {
        let image = TestImage.gradient(width: 8, height: 8)
        let cropped = try #require(Renderer.crop(image, toPixelRect: CGRect(x: 1.5, y: 1.5, width: 2, height: 2)))
        #expect(cropped.width == 3)
        #expect(cropped.height == 3)
        #expect(TestImage.pixel(cropped, x: 0, y: 0) == [1, 1, 0, 255])
    }
}
