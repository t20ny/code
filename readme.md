# process mp3 files
- main script: `process_mp3_files.ps1`
A driver will call this main script.
The main scripts calls worker scripts.
Goal is to trim and equalize the mp3 file so it has only clear even speech, with the louder sections removed,  making it ideal to listen to while going to sleep.

## trim sections
Typically the start of a mp3 file for 30 seconds up to 90 seconds will be louder than the following normal section of 5 to 15 minutes. Detect the loud section at the start and remove it in one block.
The reminder of the file may have loud sections of 30 to 90 seconds, followed by normal sections of 10 to 15 minutes, but this needs to be detected and a smart algorithm used to decide what to delete and what to retain.
The last 30 seconds of a file is typically louder and if so should be removed in one block.
Dont remove blocks if less than 5 seconds, try to interpolate other nearby block within 10 seconds and make it once contiguous block to delete. If deleting a block then expect 10 minute of normal volume level, but test this and make a smart decision.
Comare the RMS level histogram with silence log to make a good decision on what the loud sections are to be deleted.

## results
Save the run summary to `_mp3Log.json` in the selected output folder.
Each record includes the source basename, run date, mode, trimmed duration in seconds, and the output file path.

Example:
```json
[
  {
    "basename": "example_podcast",
    "date": "2026-11-12",
    "mode": 1,
    "trimmed": 420,
    "outputFile": "F:\\av\\audio\\done\\example_podcast.mp3",
    "status": "processed"
  }
]
```

The log is kept for each run so the latest result summary remains available for review.