# Threat model & security notes

## Assets

1. The **metadata fingerprint** of an image (GPS fix, device make/model, body and
   lens serial numbers, owner name/e-mail, timestamps, software versions).
2. The **plaintext payload** hidden inside a container image.
3. The **passphrase** used to derive the payload key.

## Trust boundary

The Android package declares **no `INTERNET` permission**. Every capability that
could exfiltrate data is therefore unavailable to the process:

* no HTTP client, no sockets, no WebView, no analytics SDK;
* no maps SDK (the GPS view is drawn locally with `CustomPainter`);
* no cloud backup / device transfer (`allowBackup=false`, all domains excluded);
* the Expo/Flutter debug VM service exists **only** in debug builds.

The only file-system surface is `MediaStore`: the SAF picker reads what the user
chose, and exports go to a user-chosen location or the app cache followed by the
system share sheet.

## Adversaries considered

| Adversary | Capability | Mitigation |
| --- | --- | --- |
| Social-media stranger | downloads a published photo | EXIF/XMP/IPTC/GPS stripped; JPEG scan data untouched so quality is preserved |
| Curious recipient | has the container file and the format spec | payload is AES-256-GCM ciphertext; without the passphrase nothing is recoverable |
| Passive network observer | — | nothing is ever transmitted; no network permission exists |
| Malicious local app | reads shared storage | exports are explicit user actions; app-private cache is not world-readable |
| Someone who guessed a weak passphrase | offline brute force | PBKDF2-HMAC-SHA256, 100 000 rounds, per-container random 256-bit salt |

## Cryptographic choices

* **AES-256-GCM** — authenticated encryption; a wrong password or any bit flip is
  reported as an authentication failure instead of yielding garbage plaintext.
* **PBKDF2-HMAC-SHA256, 100 000 iterations, 32-byte output** — deliberately matches
  the specification given for this project. For new deployments, Argon2id or
  scrypt would raise the cost of GPU attacks; the KDF is isolated in
  `CryptoService.deriveKey`, so swapping it is a one-method change.
* **Randomness** — `dart:math`'s `Random.secure()` on device (backed by the OS CSPRNG);
  `crypto.getRandomValues` in the browser build. Neither falls back silently in the
  Flutter path.
* **Nonce reuse** — impossible in practice: every container generates a fresh
  16-byte salt and 12-byte IV (`CryptoService.randomBytes`). The format stores both.
* **Header authentication** — magic, version, flags and cipher length are passed to
  GCM as AAD, so a tampered header cannot redirect the parser to a different
  ciphertext length.
* **Padding** — unused LSB capacity is filled with random bits, so simple
  statistical tests cannot find where the ciphertext ends.

## What this app deliberately does *not* protect against

1. **Detectability of the container.** The `SGV1` magic is plaintext, by design:
   "does this image contain a message?" is answered instantly and reliably. If
   plausible deniability is a requirement, this format is not the right tool — you
   would need a steganalysis-resistant embedder (e.g. syndrome coding or
   model-based embedding over an entire image transform), which trades capacity
   for undetectability.
2. **Compression round-trips.** Hidden data is destroyed by JPEG re-encoding,
   screenshotting, resizing or any social platform's image pipeline. Always ship
   the **PNG container file itself**.
3. **Device compromise.** Malware with root access can read memory while the app
   decrypts. The passphrase is not persisted, which limits (but does not remove)
   this window.
4. **Metadata that is not metadata.** Visual identity (faces, reflections,
   distinctive objects, sensor noise fingerprints / PRNU) survives scrubbing. The
   app removes *tags*, not *content*.
5. **Backups of the original.** The app never modifies the source file in place -
   exports are new files - but it cannot delete what already exists in a gallery or
   cloud drive.

## Verification checklist

```bash
# 1. no network capability
aapt2 dump permissions app-release.apk | grep -i internet   # expect: nothing

# 2. no cleartext traffic configuration
aapt2 dump xmltree app-release.apk --file AndroidManifest.xml | grep -i cleartext

# 3. after scrubbing, a third-party reader must see zero tags
exiftool cleaned.jpg | wc -l        # header only
identify -verbose cleaned.jpg | grep -i exif    # no EXIF block

# 4. pixels unchanged (lossless prove-out)
compare -metric AE original.jpg cleaned.jpg null:   # → 0
```

## Responsible-use note

Steganography has legitimate uses — confidential handover, watermarking your own
material, keeping a note with your own photo, journalism in hostile environments.
It is not a licence to conceal material you have no right to hold. The app is fully
offline: nobody, including the authors, can see what you embed.
