# Releasing Sunshot

1. Bump `VERSION` (`x.y.z`) and add the release to `CHANGELOG.md`. `make gate` must be green.
2. Merge to `main`, then tag the merge commit: `git tag -a vX.Y.Z -m "Sunshot X.Y.Z"` and `git push origin vX.Y.Z`.
3. `make release` builds `dist/Sunshot-X.Y.Z.zip` and its `.sha256`. Sign with a Developer ID certificate
   (`SUNSHOT_SIGN_IDENTITY="Developer ID Application: …"`) once notarisation is set up; until then the zip is
   signed with the local identity and users must Control-click ▸ Open the first time.
4. Create the GitHub release from the tag (title `Sunshot X.Y.Z`, notes from `CHANGELOG.md`) and attach the zip and
   its `.sha256`:
   `gh release create vX.Y.Z dist/Sunshot-X.Y.Z.zip dist/Sunshot-X.Y.Z.zip.sha256 --title "Sunshot X.Y.Z" --notes-file <notes>`
5. Check for Updates… in the previous version should now offer X.Y.Z (S18). The feed is
   `https://api.github.com/repos/pqBrain/SunShot/releases/latest`; it is public only while the repository is public
   (a private repository answers 404, which Sunshot shows as "No releases yet").

Drafts and pre-releases (`X.Y.Z-beta.N`, or "Set as a pre-release") are never offered to users.
