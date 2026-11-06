# Your first review

You can explore STRATHVISION without collecting training data or building a coach profile.

1. Follow [app setup](../apps/strathvision/README.md#setup) and run `flutter run -d linux` from `apps/strathvision` on Linux, or use the command for your platform.
2. Choose **New review**. On stage A, load `apps/strathvision/integration_test/assets/clip30.mp4`; on B, load `clip25.mp4`. These are generated test patterns, not athletes.
3. Scrub both to a recognizable frame and choose **Sync here**. Choose **.25×**, play, pause, and step a frame. Mirror B and confirm the sync stays intact.
4. Choose an attribute and add a green or red mark. Go back and reopen the review: clips, sync and marks should return.
5. To inspect experimental pose analysis, use `cleave.webm` from the same folder, select **Underhand**, and choose **Analyze**. Confirm the athlete selection and read warnings before inspecting measurements. The [media attribution](../apps/strathvision/integration_test/assets/ATTRIBUTION.md) identifies its source and license.

The bundled `coach_package.zip` is a **synthetic test fixture**. Import it to explore comparison screens, not to judge movement. A real profile requires sufficient distinct, usable footage of the same athlete/event and passing confidence/self-consistency gates. On desktop, resolve ambiguous selections in a review before retrying a builder clip. Copies of a video count once; distinct encodes or excerpts may still be the same recording session.

Next: [profiles and gates](wiki/Profiles.md), [architecture](ARCHITECTURE.md), then [validation limits](VALIDATION.md).
