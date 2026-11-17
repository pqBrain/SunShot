# S12 — manual checks (app-smoke)

Automated tests cover the device catalog, geometry, suggestion, rendering, undo steps, template catalog, gallery
previews, Apply Template, the default-template setting and the menu entry (`[S12-AC1]`…`[S12-AC21]`); these checks
need a person with the running app, VoiceOver and the keyboard. Tick each item when verified.

- [ ] S12-AC22 Import a phone screenshot (e.g. 1179×2556): the Device section shows "This image fits a Phone" with
      Use; Use puts the image on a Phone (Edit menu: "Undo Change Device"). With Settings ▸ "Suggest the device that
      matches imported images" off, no suggestion appears.
- [ ] S12-AC22 Device section: None / Phone / Tablet / Laptop / Monitor tiles show live device thumbnails in the
      current finish; the four finish swatches recolour the device; Orientation (Phone, Tablet only) turns it;
      Layout offers Single, Pair, Trio and the fixed combinations; "Best with … px" follows the device. Choosing a
      Frame tile removes the device, and the Frame "None" tile isn't marked while a device is shown.
- [ ] S12-AC22 VoiceOver reads each device tile ("Device: Phone, selected"), finish swatch ("Finish: Graphite,
      selected"), the Orientation and Layout pickers, and each gallery card ("Template: Pocket Spotlight, A phone on
      a sunrise gradient., current").
- [ ] S12-AC22 File ▸ Templates… (⇧⌘T) and the toolbar's Templates button open the gallery; cards show the
      current image (sample content when empty) in Screens and Devices groups; choosing one restyles the document
      and closes the sheet (Edit menu: "Undo Apply Template …"); Esc / Close dismisses it without changes.
- [ ] S12-AC22 Settings ▸ Default template lists every template; after choosing one, File ▸ New, Start Over and a
      relaunch open in it. The Annotate button is disabled while a device is shown.
- [ ] Visual: device chrome looks generic (no product shapes or logos), crisp at 1× and 2× exports, in every
      finish, on light and dark backdrops; the Device section and the gallery use the inspector's glass look in
      Light and Dark.
