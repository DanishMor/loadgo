# Signing: upload keystore aur Play App Signing (Hinglish)

Is file mein sirf commands aur steps likhe hain. Koi password, keystore ya key repo mein nahi jaati. Commands yahan se **chalaye nahi gaye**; aap khud chalayenge.

## 1. Do alag cheezein samjho
* **Upload key**: wo key jisse aap apna `.aab` sign karke Play Console par upload karte ho. Ye aapke paas rehti hai (`.jks` file).
* **App signing key**: wo key jisse Google user ko jaane wala final app sign karta hai. **Play App Signing** on rakho (naye app par default on hai), to ye key Google sambhalta hai.
* Fayda: upload key kho jaye to Play Console support se naya upload key reset ho sakta hai. Bina Play App Signing ke key khoyi to app kabhi update nahi hoga.

## 2. Upload keystore banana (ek baar, keytool se)
PowerShell mein (JDK ka `keytool` chahiye; Android Studio ke `jbr\bin\keytool.exe` mein hota hai). File repo ke **bahar** banao, jaise `C:\keys\loadgo-upload.jks`:

```powershell
New-Item -ItemType Directory -Force C:\keys
& "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v `
  -keystore C:\keys\loadgo-upload.jks -alias upload `
  -keyalg RSA -keysize 2048 -validity 10000
```
keytool khud password, naam, sheher poochhega. Password aap type karoge, kahin likhna nahi hai is repo mein.

## 3. Keystore kahan rakhna
* **Repo ke bahar** (`C:\keys\`), kabhi `C:\projects\loadgo` ke andar nahi. `.gitignore` mein `*.jks`, `*.keystore` aur `key.properties` pehle se hain, phir bhi bahar rakho.
* **Do jagah backup**: (1) encrypted pen drive ya external disk, (2) apna private cloud (password-protected zip ya password manager ka file attachment). Dono alag jagah, alag ghar/account mein.
* **Password manager** (Bitwarden, 1Password, KeePass) mein store password, key password, alias, aur file kahan rakhi hai ka note. Kagaz par ek copy ghar ki tijori mein bhi chalegi.
* WhatsApp, e-mail ya chat par keystore ya password mat bhejna.

## 4. `android/key.properties` ka format
Ye file git-ignored hai (`android/key.properties`), commit nahi hoti. `android/app/build.gradle.kts` isse padhta hai:

```
storeFile=C:/keys/loadgo-upload.jks
storePassword=<apna store password>
keyAlias=upload
keyPassword=<apna key password>
```
* `storeFile` mein `/` use karo (Windows mein bhi), `\` nahi.
* Ye file na ho to release build **debug key** se sign hoti hai aur Play use reject karega.

## 5. Build aur check
```powershell
flutter build appbundle --release      # upload ke liye (chalane se pehle docs/PLAY_SUBMISSION_STEPS.md)
```
Upload key ka SHA-1 / SHA-256 dekhne ke liye (sirf terminal mein, repo mein mat likho):
```powershell
& "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe" -list -v -keystore C:\keys\loadgo-upload.jks -alias upload
```
Is SHA ko Firebase app mein jodna hai. **Play App Signing ke baad** Play Console > Setup > App signing mein Google ki app signing key ka SHA-1/SHA-256 bhi dikhega; Phone login aur Google sign-in ke liye wo bhi Firebase mein jodo (aur `hosting/.well-known/assetlinks.json` mein).

## 6. Play App Signing on karna
1. Play Console mein app banao, **Release > Setup > App signing** kholo.
2. "Use Play App Signing" rakho, pehla `.aab` upload karo (upload key se signed).
3. Google final key rakhega; aapko sirf upload key sambhalni hai.
4. Upload key ka certificate Console mein dikhega: apne keytool wale SHA se match karke verify karo.

## 7. Galti ho jaye to
* Upload keystore ya password kho gaya: Play Console > App signing > "Request upload key reset" (Google naya upload certificate le lega). Isiliye Play App Signing on rakhna zaroori hai.
* Keystore repo mein commit ho gaya: foran Console se upload key reset karo, history se hatao, aur naya keystore banao. `docs/SECRETS_AUDIT.md` ka check dobara chalao.
* Debug key se bana APK sirf test ke liye hai, store par nahi.

## 8. Test
`test/signing_ignore_test.dart` sabit karta hai ki `*.jks`, `*.keystore` aur `key.properties` (kisi bhi folder mein) git ignore karta hai.
