# FK8 Video Tools

Two free tools for the stock 7 inch head unit in the 10th gen Civic:

- **Make Startup Video** turns a clip into a custom startup video.
- **Convert Film** turns a long video into a file that plays properly from a USB stick.

Built and tested on my 2018 Civic Type R (FK8, UK). It should suit any 10th gen Civic with the same unit, but I've only tested mine.

You don't need to know PowerShell or FFmpeg. Double-click a file, pick your video and press one button.

## What you need

- A Windows PC (Mac instructions are further down)
- A USB stick of 32 GB or smaller
- [Honda Hack](http://www.autohack.org) on the head unit, for startup videos
- Your own video file

## Download

**[Download FK8 Video Tools (zip)](https://github.com/WilbyFast/fk8-video-tools-v3/archive/refs/heads/main.zip)**

1. Click the link above.
2. Right-click the downloaded zip and choose **Extract All**. The tools won't run from inside the zip.
3. Open the new folder.

The first time you run either tool it fetches FFmpeg, the free program that does the converting. That's about 200 MB, it shows its progress, and it happens once.

If Windows shows a blue "Windows protected your PC" box, click **More info**, then **Run anyway**. It appears because the file came from the internet.

## Tool 1: Make Startup Video

1. Double-click **Make Startup Video.bat**. A small window opens.
2. Click **Choose video**, or drag your clip onto the window.
3. Type where the clip should start, and set how long it should run. 20 seconds is the default.
4. Click **Preview clip** to watch exactly what you'll get.
5. Click **Make startup video**.

The result is saved next to your original, ending in `_startup.mp4`, and its folder opens when it's done.

**Putting it on the car.** Copy the file to the USB stick and plug it in. Open Honda Hack, go to the startup video menu and choose it. Set Honda Hack's maximum play time longer than your clip, or it cuts off after a few seconds.

## Tool 2: Convert Film

1. Double-click **Convert Film.bat**.
2. Click **Choose video**, or drag your video onto the window.
3. If the file has more than one soundtrack, pick the one you want.
4. Click **Convert film**. A black window shows the progress. A full film can take 20 minutes or more.

The result is saved next to your original, ending in `_car.mp4`.

**Playing it.** Copy the file to the USB stick, plug it in and play it from the USB source. Video only plays when you're parked with the handbrake on. Leave it that way.

## The USB stick

Use a stick of 32 GB or smaller, formatted as FAT32. The head unit can't read anything else.

To format it, right-click the stick in Windows, choose **Format**, pick **FAT32** and click Start. This wipes the stick.

FAT32 can't hold a single file over 4 GB. Convert Film lowers the bitrate on very long films so they stay under that. A 32 GB stick holds about ten films.

## What the tools do to your video

| | Startup video | Film |
| --- | --- | --- |
| Picture size | 848x480 | 800x480 |
| Video format | MPEG-4, about 9.5 Mbps | H.264 Baseline, level 3.1 |
| Bitrate | High on purpose. The clip is short and a low bitrate looks blocky on this screen. | Quality-based, capped at 3 Mbps, so a 2 hour film is about 3 GB |
| Frame rate | Same as the source, 30 max | Same as the source, 30 max |
| Audio | AAC stereo, 192k | AAC stereo, 160k. Surround tracks are mixed down because they often play silent. |
| Length | 20 seconds by default | Whole video |

The startup settings match the clips running on my own car. The numbers sit at the top of `convert.ps1` if you want to change them.

## Mac

Install FFmpeg first (`brew install ffmpeg`), then in Terminal:

```
bash convert.sh startup "my clip.mp4"
bash convert.sh film "my film.mkv"
```

## If something goes wrong

- **Startup clip stops after a few seconds.** Raise the maximum play time in Honda Hack.
- **Plays with no sound.** Run Convert Film again and pick a different soundtrack.
- **Colours look washed out.** The source is probably HDR. Use an SDR version.
- **Stutters or won't play.** Lower `$StartupBitrate` or `$FilmMaxBitrate` at the top of `convert.ps1` and try again.
- **The stick doesn't show up.** It isn't FAT32, or it's bigger than 32 GB.
- **Nothing happens when you double-click.** You're running it from inside the zip. Extract it first.
- **"Doesn't look like a video FFmpeg can read".** The file is damaged or copy-protected.

If you get stuck, open an Issue on this page and tell me your car, your Honda Hack version and what happened.

## What these tools don't do

- They don't download or supply any video. You bring your own file.
- They can't open copy-protected files and don't remove copy protection.
- They change nothing on the car. They only make a video file on your PC.

Only convert videos you own or have the right to use.

## Disclaimer

A hobby project, provided as is. Not affiliated with or endorsed by Honda or Honda Hack. Names are used only to say which car and unit the tools are for.

FFmpeg isn't part of this repo. The tool fetches it from [BtbN's FFmpeg builds](https://github.com/BtbN/FFmpeg-Builds), and it is licensed separately under the GPL.

## Licence

MIT. See `LICENSE`.
