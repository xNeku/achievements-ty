import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Ventana horizontal tipo tablet, centrada, con fondo oscuro desde el arranque.
    let size = NSSize(width: 1280, height: 800)
    self.setContentSize(size)
    self.contentMinSize = NSSize(width: 900, height: 560)
    self.title = "Hangar"
    self.titlebarAppearsTransparent = true
    self.backgroundColor = NSColor(red: 0.04, green: 0.03, blue: 0.035, alpha: 1)
    self.appearance = NSAppearance(named: .darkAqua)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
