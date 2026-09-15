# Prompt Tawa & Dialog Badut — ElevenLabs v3 (Audio Tags)

Cara pakai: model **eleven_v3**, Stability **Creative**, satu baris = satu generate.
Generate 2–3 kali per baris, pilih take terbaik.

Tag resmi v3 yang dipakai di bawah:
`[laughs]` `[laughs harder]` `[starts laughing]` `[giggles]` `[wheezing]` `[snorts]`
`[whispers]` `[sighs]` `[exhales]` `[curious]` `[excited]` `[crying]` `[sarcastic]`
`[mischievously]` `[swallows]` `[gulps]` `[sings]` `[woo]`

---

## 1. SADAR ADA PEMAIN (TargetAcquired)

```
[sniffs] [curious] ...What's that smell? [giggles] Fresh meat... in MY carnival? [starts laughing] [excited]
```
```
[whispers] [curious] Did you hear that...? [snorts] [mischievously] I think someone's playing hide and seek with me. [giggles] [starts laughing]
```
```
[sings] La la la la la... [stops] [curious] ...who's there? [giggles] [mischievously] Ohhh, a visitor! [laughs] [claps] [laughs harder]
```
```
[gulps] [curious] Something moved... [snorts] [excited] Ohhh I HOPE it's a child! [giggles] [starts laughing] [laughs harder]
```

## 2. MULAI MENGECAR (CHASING)

```
[laughs] Run, little mouse... RUN! [laughs harder] [wheezing] The maze belongs to ME!
```
```
[starts laughing] There you are!! [laughs harder] [excited] COME BACK HERE!
```
```
[laughs] You can run... [wheezing] but you can't hide... [laughs harder] NOT IN MY CARNIVAL!
```
```
[woo] Faster, faster! [laughs] [mischievously] The clown is catching up! [laughs harder] [snorts]
```
```
[laughs] Hee— [snorts] —heh heh... [wheezing] You're getting slow, little one. [laughs harder] [excited]
```

## 3. MENYERANG (ATTACKING)

```
[laughs harder] FOUND YOU!! [laughs harder] [excited] NOW YOU'RE MINE!!
```
```
[laughs harder] GOTCHA!! [wheezing] No more hiding... [whispers] NO MORE HIDING!
```
```
[starts laughing] [laughs harder] [woo] GOTCHA GOTCHA GOTCHA!! [snorts] [laughs harder]
```

## 4. KEHILANGAN TARGET (TargetLost)

```
[laughs] Where did you go... [sighs] where did you GO?! [snorts] [crying] Come back... COME BACK!
```
```
[giggles] Hiding again? [crying] That's not fair... [sarcastic] that's NOT FAIR! [snorts] [sighs]
```
```
[sighs] [wheezing] Fine... [mischievously] I'll wait. [giggles] I'm VERY good at waiting. [starts laughing]
```

## 5. MENGANCAM PELAN (dialog jarak dekat)

```
[whispers] You made my carnival so... quiet. [mischievously] And I was going to share my balloon with you. [giggles] [laughs]
```
```
[whispers] [wheezing] I can hear your heartbeat... [excited] it's SO fast! [giggles] [laughs harder]
```
```
[sarcastic] Ohhh, you're a clever one, aren't you? [snorts] [mischievously] I LOVE clever ones. [laughs] [laughs harder]
```

## 6. AMBIENCE / LAYER NONVERBAL (tanpa kata)

```
[wheezing] [exhales] [wheezing] [exhales]
```
```
[snorts] [wheezing] [gulps] [wheezing] [exhales]
```
```
[giggles] [sighs] [giggles] [snorts]
```

## 7. TAWA MURNI (untuk loop / sting)

```
[starts laughing] [laughs harder] [wheezing] [laughs harder]
```
```
[giggles] [laughs] [laughs harder] [laughs harder] [snorts]
```
```
[mischievously] [giggles] [starts laughing] [laughs harder] [woo]
```

---

## Catatan Teknis

- **CAPS** = naik emphasis/volume. **`...`** = jeda berat. **`—`** = jeda pendek tajam.
- v3 **tidak** mendukung `<break>` — pakai ellipsis/dash saja.
- Tag tidak akan menolong kalau voice-nya salah karakter (voice berat tidak bisa melengking).
- Kalau hasil kurang edan: klik **Enhance** di UI, lalu edit manual.
