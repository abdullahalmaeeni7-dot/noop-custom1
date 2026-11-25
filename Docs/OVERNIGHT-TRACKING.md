# Using the tracker overnight

## Check the connection

Open Device Settings from the tracker icon on Home. Wear the band and look for **Receiving data** and an increasing saved-reading count. Once paired, the app asks iOS to reconnect to the saved band when it comes back into range. After an iPhone restart, unlock the phone once so the app can access saved measurements. Force-quitting the app can interrupt background delivery.

With a supported band, removing it shows **Tracker off body** on Home and in Device Settings when the strap sends a wrist-removal event or a heart-rate contact flag. The app stops accepting off-body readings. A Bluetooth disconnect or a quiet stream alone leaves wear status unknown.

If Device Settings offers **Automatically sync stored readings**, enable it to collect the strap’s available history after reconnection. Each complete batch is saved before the app confirms receipt. Which fields are available depends on the strap and firmware.

## See last night’s sleep

- **If your sleep is in Apple Health**, open **Device Settings → Automatic Sleep**, enable **Automatically sync sleep**, and allow Sleep access. The app reads the past seven days, groups time asleep by local wake date, and refreshes on background delivery or when reopened. A sleep-recording device or app needs to have written the sleep session to Apple Health. Installation requires a signing profile with HealthKit capabilities.
- **If your sleep is in your WHOOP account**, open **More → WHOOP account**, link the account through your configured bridge, and enable **Automatically sync recent WHOOP data**. The app refreshes the latest 14 days on opening. You can also import an exported WHOOP ZIP through the import screen. These sources can supply the official Sleep Performance, Recovery and Strain scores once WHOOP has calculated them.
- **If you used only the paired band**, look for **Review overnight rest** on Home or in Sleep. With a recently measured resting-heart-rate baseline, the app looks for at least two continuous hours of readings near that baseline with confirmed wrist contact. Without that history, the first-night check requires at least four continuous hours at 40–75 bpm, including at least two hours between local midnight and 6 a.m. A gap or an overlapping workout breaks the candidate interval. Adjust the times to when you were actually asleep, then tap **I was asleep · Save**. The entry remains editable in Sleep. If there’s no suitable interval, **Sleep → Log sleep** lets you enter times you know.

Time asleep appears on the Home ring when a duration exists and the provider has supplied no performance percentage. A manually confirmed duration is labeled in My Day. Confirming sleep does not generate sleep stages or a Recovery score. If neither the app, a provider nor the band retained readings for a past night, its measurements cannot be reconstructed.

## See activity as it happens

Home shows **Possible activity in progress** after five minutes of elevated heart rate at or above 50% of heart-rate reserve. The detector uses the resting and maximum values in Device Settings and requires ongoing readings with gaps of at most 15 seconds. My Day records the interval as a possible activity. You can edit the activity type or remove it. Manually recorded and imported workouts take precedence when intervals overlap.
