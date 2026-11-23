# KBPulse Profiles

Profiles are JSON documents decoded into `Theme`. Missing fields get defaults. `Theme.validate()` reports values that would not play correctly.

## Top-Level
```swift
struct Theme
```

### Name
```json
"Name" : "Cool Profile",
```
```swift
var name: String
```
**Required**. Should generally match your file name, but you can add extra details here (i.e. `theme_slow.json` can have `Theme (slow)` for `Name`. It can technically be anything, but try not to be confusing to the user.

### Version
```json
"Version" : "1.0.0",
```
```swift
var version: String
```
*Optional but recommended*. Try to use the MAJOR.MINOR.PATCH semantic versioning format.

### Description
```json
"Description" : "A short description of your profile in a calm fragment that makes a comparison at the end",
```
```swift
var comment: String
```
*Optional*. You can put anything into the description, but I put extra effort into coming up with the "style" of the built-in profiles' descriptions. There's a formula:

> (A/an) (short adjective), (adverb comparison) animation that (comparison to something familiar).

If you want to follow this formula, remember to not make a complete sentence. Your description should be a sentence fragment, and more specifically, a subject (or noun) fragment. The description should describe the profile's attributes, not its actions.

### Author
```json
"Author" : "EthanRDoesMC",
```
```swift
var author: String
```
*Optional but recommended*.

### Homepage
```json
"Homepage" : "https://github.com/EthanRDoesMC/KBPulse/",
```
```swift
var homepage: String
```
*Optional*. Try not to use *your* homepage. Instead, try to link to the website (or GitHub repo/gist) *for the profile*.

### Preview Image URL
```json
"Preview Image URL" : "https://example.com/image.jpeg",
```
```swift
var previewImageURL: String
```
*Optional*. Not a big priority, but should I implement a UI one day, it would be really nice if community profiles already had preview images.

### Haptics
```json
"Haptics" : true,
```
```swift
var haptics: Bool
```
*Optional, default false.* When true, KBPulse taps the trackpad at each animation beat or typing bump. The user must also turn on **Trackpad haptics** in Settings > General. Works for animation themes and reactive themes.

## Animations
```json
"Animations" = [
    {
        ...
    },
    ...
],
```
    
```swift
var animations: [Theme.Animation]
```

### Name
**Required**. Shown in the editor.

### Description
Same as above, but optional. *This* description is for *your* reference, so you don't have to worry about making it nice.

### Brightness
```json
"Brightness" : 0.5,
```
```swift
var brightness: Double
```
**Required**. Any `double` between and including 0.0 and 1.0. The brightness value that the backlight will be set to.

### Fade Duration
```json
"Fade Duration" : 2500,
```
```swift
var fadeDuration: Double
```
**Required**. Milliseconds for how long the brightness fade-in will take. Fractional values are allowed.

### Delay
```json
"Delay" : 2500,
```
```swift
var delay: Double
```
**Required**. Milliseconds that KBPulse waits *after* the current fade animation completes before starting the next animation. Fractional values are allowed.