# S14 — manual checks (app-smoke)

Automated tests cover the batch model, file collection, naming, thumbnails, export, progress, cancel and error
aggregation (`[S14-AC1]`–`[S14-AC17]`); these checks need a person in the running app. Tick each item when it has
been verified.

- [ ] S14-AC18 File ▸ Import Multiple… (⇧⌘O) opens a panel that allows several files and folders; after picking,
      the preview strip appears under the editor with one thumbnail per image, the count and Export All….
- [ ] S14-AC18 Dropping several images, or a folder, onto the canvas adds them to the strip; dropping one image
      still opens it on its own.
- [ ] S14-AC18 Changing a style control (radius, shadow, backdrop, canvas size) updates the canvas and every
      thumbnail; ⌘Z undoes the style change without changing the selected image.
- [ ] S14-AC18 File ▸ Export All… (⌥⇧⌘E) asks for a folder, shows a progress bar with "Exporting 3 of 12" and
      Cancel, then a summary with Show in Finder; Export All is disabled while it runs and with no batch.
- [ ] S14-AC18 A corrupt file in the batch shows an error badge in the strip and is listed in the export summary;
      the other files are exported.
- [ ] S14-AC19 VoiceOver reads each thumbnail ("Image 2 of 12, shot.png, selected"); ← / → move the selection,
      ⌫ removes the selected item; the context menu offers Move Left, Move Right and Remove from Batch; dragging a
      thumbnail onto another reorders.
- [ ] Visual: the strip, progress and summary use the translucent glass look of the rest of the window, in Light
      and Dark.
