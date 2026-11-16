"""Mux video + music, with the music set to -15 LUFS (two-pass loudnorm).

usage: python3 mux.py video.mp4 music.wav out.mp4
"""
import json
import subprocess
import sys

video, wav, out = sys.argv[1:4]
TARGET = 'I=-15:TP=-1.5:LRA=11'
p = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', wav, '-af', f'loudnorm={TARGET}:print_format=json', '-f', 'null', '-'],
                   capture_output=True, text=True)
m = json.loads(p.stderr[p.stderr.rindex('{'):p.stderr.rindex('}') + 1])
af = (f"loudnorm={TARGET}:measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}"
      f":measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true,aresample=48000")
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', video, '-i', wav, '-map', '0:v', '-map', '1:a', '-c:v', 'copy',
                '-af', af, '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', '-shortest', out], check=True)
# measure the result
p = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', out, '-af', 'ebur128', '-f', 'null', '-'], capture_output=True, text=True)
lufs = [ln for ln in p.stderr.splitlines() if ln.strip().startswith('I:')][-1].split()[1]
print(f'{out}: {lufs} LUFS')
