# All Video Score Summary

Run dir: `outputs/all_video_scores_20260511_224820`

Sampling: default `sampleInterval = 0.2s` (5fps); thresholds are duration-based.

## Group Averages

| group | count | avg score | min | max |
| --- | ---: | ---: | ---: | ---: |
| bad | 9 | 57.6 | 49 | 70.2 |
| good | 15 | 74.7 | 66.5 | 89.3 |
| middle | 20 | 66.4 | 55.1 | 85.3 |
| testvideo | 6 | 64.7 | 55.1 | 81.6 |
| all | 50 | 67.1 | 49 | 89.3 |

## Ablation Scores

| group | raw | best 1/3 | capped | flow x | final | video |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| testvideo | 52.7 | 59.5 | 58 | 1.03 | 59.7 | `testvideo/1.MP4` |
| testvideo | 61.9 | 69.1 | 58 | 0.95 | 55.1 | `testvideo/2.MP4` |
| testvideo | 74.8 | 85.9 | 85.9 | 0.95 | 81.6 | `testvideo/3.MP4` |
| testvideo | 70.5 | 70.5 | 65 | 1.08 | 70.2 | `testvideo/4.MP4` |
| testvideo | 54.6 | 62.2 | 58 | 0.95 | 55.1 | `testvideo/5.mp4` |
| testvideo | 71.1 | 81.2 | 70 | 0.95 | 66.5 | `testvideo/6.MP4` |
| bad | 63.8 | 71.3 | 65 | 1.08 | 70.2 | `video/bad/0b7522e9db823b910ac67727aea726da.MP4` |
| bad | 63.1 | 76.3 | 58 | 1.03 | 59.7 | `video/bad/v0200fg10000d6olrffog65vrste5qqg.MOV` |
| bad | 60.9 | 64.4 | 58 | 0.95 | 55.1 | `video/bad/v0200fg10000d7nnh5vog65i52ermgog.MP4` |
| bad | 50.1 | 53.3 | 53.3 | 1.08 | 57.6 | `video/bad/v0300fg10000cusoptnog65pkehng280.MP4` |
| bad | 47.1 | 47.6 | 47.6 | 1.03 | 49 | `video/bad/v0300fg10000d664l37og65t6pnbois0.MOV` |
| bad | 51.2 | 51.7 | 51.7 | 0.95 | 49.1 | `video/bad/v0d00fg10000csgr6inog65n8mlpg2m0.MP4` |
| bad | 67 | 74.2 | 58 | 0.95 | 55.1 | `video/bad/v0d00fg10000ctm0ufvog65rqb97g2p0.MP4` |
| bad | 59 | 66.9 | 62 | 0.95 | 58.9 | `video/bad/v1e00fgi0000cv786ffog65rtmm48gmg.MOV` |
| bad | 75.6 | 79.1 | 62 | 1.03 | 63.9 | `video/bad/v2800fgi0000d4v24r7og65oi0fmka5g.MP4` |
| good | 62.8 | 70.6 | 70.6 | 1.03 | 72.7 | `video/good/0946ed384e732c357a3d55fac77426c0.MP4` |
| good | 67.9 | 76 | 76 | 0.95 | 72.2 | `video/good/3134552bed78447b9f7ba8e2003ce678.MP4` |
| good | 69.2 | 87.6 | 87.6 | 0.95 | 83.2 | `video/good/3e6f37fe76521781506c19c02c1b97ed.MP4` |
| good | 62.1 | 71.5 | 70 | 1.03 | 72.1 | `video/good/5382da0c825e30518ab376505cbcfaf2.MOV` |
| good | 82.2 | 88.5 | 88.5 | 0.87 | 77 | `video/good/641efed02be271b6d9f014c97d1f8ae0.MOV` |
| good | 61.2 | 70.9 | 70.9 | 0.95 | 67.3 | `video/good/86ae42724c8349913703af0f4140f6d2.MP4` |
| good | 59 | 72.9 | 79.1 | 0.95 | 75.1 | `video/good/9ed0bb6c707fc47fce153cee3dcd365e.MP4` |
| good | 72.8 | 79.6 | 70 | 0.95 | 66.5 | `video/good/d63bfbf8978cf8a962f613a489a14420.MP4` |
| good | 66.5 | 77.9 | 77.9 | 0.95 | 74 | `video/good/v0200fg10000d6mln8vog65kajcq52dg.MP4` |
| good | 81 | 94 | 94 | 0.95 | 89.3 | `video/good/v0200fg10000d7r0017og65qoh1vgeg0.MP4` |
| good | 67.5 | 72.9 | 70 | 0.95 | 66.5 | `video/good/v0300fg10000d7h0ckfog65nmsn20jqg.MP4` |
| good | 62.5 | 71.3 | 70 | 1.03 | 72.1 | `video/good/v1e00fgi0000d2bufenog65temc6sh70.MP4` |
| good | 70.4 | 83.2 | 83.2 | 0.95 | 79 | `video/good/v1e00fgi0000d5utfk7og65q1chsrq8g.MP4` |
| good | 71.4 | 78.4 | 78.4 | 1 | 78.4 | `video/good/v2800fgi0000d6m0mk7og65qamcvgf80.MP4` |
| good | 72.2 | 72.8 | 72.8 | 1.03 | 75 | `video/good/v2800fgi0000d7o00ufog65t0ran4h1g.MP4` |
| middle | 65 | 65 | 65 | 1.03 | 66.9 | `video/middle/1c5771fc7dd1ea546eb5bc3e4e01bc48.MP4` |
| middle | 74.7 | 76.9 | 76.9 | 0.95 | 73.1 | `video/middle/4a7dfe960f07ac14b06bbd8de3d38aa4.MP4` |
| middle | 62.2 | 72.7 | 58 | 1.03 | 59.7 | `video/middle/4f9ec73b994b63b0775ccfb7a8ef7e6f.MP4` |
| middle | 81.4 | 85.3 | 85.3 | 1 | 85.3 | `video/middle/96001e37e76be9ef6cf7a65e73efcac4.MP4` |
| middle | 74 | 79.2 | 79.2 | 0.95 | 75.3 | `video/middle/9714be3aba73f5f94130750c2a15d381.MP4` |
| middle | 57.9 | 64.5 | 58 | 0.95 | 55.1 | `video/middle/992f063b79d27b96b471e44a48d8465e.MP4` |
| middle | 67.6 | 72 | 72 | 1.03 | 74.1 | `video/middle/a7791a475a244c938dd0815e89b1dec5.MP4` |
| middle | 74 | 83.9 | 70 | 1.03 | 72.1 | `video/middle/b343b317a6689df373085ec85e042480.MP4` |
| middle | 64.6 | 72 | 72 | 0.95 | 68.4 | `video/middle/ccfd9967aa6d3ab5abd04fb8991872c7.MOV` |
| middle | 69.3 | 77.3 | 58 | 0.95 | 55.1 | `video/middle/v0200fg10000coc7bcrc77u875h9q7sg.MP4` |
| middle | 53.6 | 58.2 | 58 | 1 | 58 | `video/middle/v0200fg10000d2tcts7og65t6h63ua2g.MP4` |
| middle | 55.4 | 63.1 | 58 | 0.95 | 55.1 | `video/middle/v0200fg10000d318sovog65g16lolm8g.MP4` |
| middle | 68.9 | 80.2 | 80.2 | 0.95 | 76.2 | `video/middle/v0200fg10000d6a4i57og65mkjkcdpu0.MP4` |
| middle | 55.3 | 66.4 | 58 | 1.03 | 59.7 | `video/middle/v0300fg10000d4oq6avog65ihr8qf550.MP4` |
| middle | 62.6 | 62.6 | 58 | 1.08 | 62.6 | `video/middle/v0300fg10000d5h313fog65nermuqklg.MP4` |
| middle | 61 | 61 | 55 | 1.13 | 62.2 | `video/middle/v0300fg10000d6fe0nnog65jmdun29vg.MP4` |
| middle | 65.9 | 69.3 | 69.3 | 1.03 | 71.4 | `video/middle/v0d00fg10000cu3omkvog65r22seg0t0.MP4` |
| middle | 58.4 | 63.6 | 58 | 1.03 | 59.7 | `video/middle/v1e00fgi0000d5bksdfog65irrhr4bog.MP4` |
| middle | 66.8 | 74.8 | 65 | 0.95 | 61.8 | `video/middle/v2800fgi0000d54jhefog65lbfdhma2g.MP4` |
| middle | 66.6 | 74.7 | 74.7 | 1.03 | 76.9 | `video/middle/v2800fgi0000d5ehg1vog65tinkepgl0.MP4` |

## Scores

| group | score | level | edge | sideslip | carving | flow coh | flow stable | flow smooth | video |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| testvideo | 59.7 | 初级 | 35.8 | 21 | 58.6 | 65 | 100 | 0 | `testvideo/1.MP4` |
| testvideo | 55.1 | 初级 | 44.8 | 22.3 | 50.5 | 24.1 | 66.5 | 0 | `testvideo/2.MP4` |
| testvideo | 81.6 | 高级 | 63.8 | 20.6 | 55.4 | 48.9 | 92.5 | 0 | `testvideo/3.MP4` |
| testvideo | 70.2 | 中级 | 55.4 |  |  | 64.2 | 100 | 100 | `testvideo/4.MP4` |
| testvideo | 55.1 | 初级 | 44.2 | 34.6 | 51 | 43.5 | 66.2 | 0 | `testvideo/5.mp4` |
| testvideo | 66.5 | 中级 | 68.2 | 37 | 28.4 | 34.6 | 47.3 | 0 | `testvideo/6.MP4` |
| bad | 70.2 | 中级 | 51.7 | 17 | 62.2 | 78.2 | 99.6 | 0 | `video/bad/0b7522e9db823b910ac67727aea726da.MP4` |
| bad | 59.7 | 初级 | 49.8 | 17 | 63 | 56.6 | 80.4 | 0 | `video/bad/v0200fg10000d6olrffog65vrste5qqg.MOV` |
| bad | 55.1 | 初级 | 46.3 | 14.5 | 67.8 | 33.1 | 56.7 | 0 | `video/bad/v0200fg10000d7nnh5vog65i52ermgog.MP4` |
| bad | 57.6 | 初级 | 35.9 | 2.2 | 95 | 84.8 | 100 | 0 | `video/bad/v0300fg10000cusoptnog65pkehng280.MP4` |
| bad | 49 | 初级 | 31.9 | 77.7 | 0 | 34.1 | 100 | 0 | `video/bad/v0300fg10000d664l37og65t6pnbois0.MOV` |
| bad | 49.1 | 初级 | 38.9 | 20.9 | 53.4 | 14.9 | 67.9 | 0 | `video/bad/v0d00fg10000csgr6inog65n8mlpg2m0.MP4` |
| bad | 55.1 | 初级 | 48.3 | 27.8 | 44 | 51.8 | 65.2 | 0 | `video/bad/v0d00fg10000ctm0ufvog65rqb97g2p0.MP4` |
| bad | 58.9 | 初级 | 53.5 | 22.4 | 57.6 | 15.7 | 5 | 0 | `video/bad/v1e00fgi0000cv786ffog65rtmm48gmg.MOV` |
| bad | 63.9 | 中级 | 68.1 | 16.1 | 64.2 | 31.6 | 100 | 0 | `video/bad/v2800fgi0000d4v24r7og65oi0fmka5g.MP4` |
| good | 72.7 | 中级 | 60.5 | 17 | 62.2 | 21.8 | 100 | 0 | `video/good/0946ed384e732c357a3d55fac77426c0.MP4` |
| good | 72.2 | 中级 | 68.5 | 30.6 | 54.6 | 29.6 | 100 | 0 | `video/good/3134552bed78447b9f7ba8e2003ce678.MP4` |
| good | 83.2 | 高级 | 68.5 | 17.5 | 73 | 49.5 | 99.2 | 0 | `video/good/3e6f37fe76521781506c19c02c1b97ed.MP4` |
| good | 72.1 | 中级 | 61.4 | 39.7 | 25.7 | 5.1 | 73.8 | 0 | `video/good/5382da0c825e30518ab376505cbcfaf2.MOV` |
| good | 77 | 高级 | 79.3 | 28.9 | 48.1 | 51.3 | 11.5 | 0 | `video/good/641efed02be271b6d9f014c97d1f8ae0.MOV` |
| good | 67.3 | 中级 | 56.3 | 13.8 | 75.9 | 49.2 | 35 | 0 | `video/good/86ae42724c8349913703af0f4140f6d2.MP4` |
| good | 75.1 | 高级 | 46.8 | 54.6 | 13.9 | 34.3 | 97.1 | 0 | `video/good/9ed0bb6c707fc47fce153cee3dcd365e.MP4` |
| good | 66.5 | 中级 | 61.1 | 31.3 | 45.6 | 64.4 | 61.1 | 0 | `video/good/d63bfbf8978cf8a962f613a489a14420.MP4` |
| good | 74 | 中级 | 60.6 | 32.1 | 43 | 39.9 | 38.5 | 0 | `video/good/v0200fg10000d6mln8vog65kajcq52dg.MP4` |
| good | 89.3 | 专业 | 70.3 | 30.5 | 32.3 | 67.2 | 95.1 | 0 | `video/good/v0200fg10000d7r0017og65qoh1vgeg0.MP4` |
| good | 66.5 | 中级 | 63.1 | 31.6 | 33.1 | 51.9 | 52.6 | 0 | `video/good/v0300fg10000d7h0ckfog65nmsn20jqg.MP4` |
| good | 72.1 | 中级 | 58.1 | 36.8 | 30.2 | 48.4 | 80.2 | 0 | `video/good/v1e00fgi0000d2bufenog65temc6sh70.MP4` |
| good | 79 | 高级 | 61.5 | 8.5 | 81.2 | 28.9 | 79.8 | 0 | `video/good/v1e00fgi0000d5utfk7og65q1chsrq8g.MP4` |
| good | 78.4 | 高级 | 75.3 | 30.3 | 33.3 | 93.6 | 100 | 0 | `video/good/v2800fgi0000d6m0mk7og65qamcvgf80.MP4` |
| good | 75 | 中级 | 71.9 | 37.4 | 21.1 | 56.5 | 100 | 0 | `video/good/v2800fgi0000d7o00ufog65t0ran4h1g.MP4` |
| middle | 66.9 | 中级 | 47.4 |  |  | 25.5 | 100 | 0 | `video/middle/1c5771fc7dd1ea546eb5bc3e4e01bc48.MP4` |
| middle | 73.1 | 中级 | 73.5 | 31.9 | 31.8 | 53.8 | 100 | 0 | `video/middle/4a7dfe960f07ac14b06bbd8de3d38aa4.MP4` |
| middle | 59.7 | 初级 | 53.3 | 55.7 | 4.5 | 54.4 | 100 | 0 | `video/middle/4f9ec73b994b63b0775ccfb7a8ef7e6f.MP4` |
| middle | 85.3 | 专业 | 75.4 | 9.8 | 78.2 | 71.7 | 100 | 0 | `video/middle/96001e37e76be9ef6cf7a65e73efcac4.MP4` |
| middle | 75.3 | 高级 | 61.6 | 27.9 | 55.2 | 45.9 | 92.9 | 0 | `video/middle/9714be3aba73f5f94130750c2a15d381.MP4` |
| middle | 55.1 | 初级 | 41.5 | 60.8 | 3.3 | 48.7 | 69.4 | 0 | `video/middle/992f063b79d27b96b471e44a48d8465e.MP4` |
| middle | 74.1 | 中级 | 59 | 17.2 | 61.8 | 54 | 82.4 | 0 | `video/middle/a7791a475a244c938dd0815e89b1dec5.MP4` |
| middle | 72.1 | 中级 | 71.5 | 41.9 | 23.5 | 36.4 | 98 | 0 | `video/middle/b343b317a6689df373085ec85e042480.MP4` |
| middle | 68.4 | 中级 | 65.7 | 6.4 | 85.7 | 36.1 | 45.4 | 0 | `video/middle/ccfd9967aa6d3ab5abd04fb8991872c7.MOV` |
| middle | 55.1 | 初级 | 50.8 | 45.8 | 26.9 | 65.5 | 30.9 | 0 | `video/middle/v0200fg10000coc7bcrc77u875h9q7sg.MP4` |
| middle | 58 | 初级 | 38.7 | 35.9 | 31 | 70.8 | 46 | 0 | `video/middle/v0200fg10000d2tcts7og65t6h63ua2g.MP4` |
| middle | 55.1 | 初级 | 45.5 | 72.9 | 0 | 49.3 | 41.8 | 0 | `video/middle/v0200fg10000d318sovog65g16lolm8g.MP4` |
| middle | 76.2 | 高级 | 59.6 | 13.4 | 73.5 | 55.6 | 100 | 0 | `video/middle/v0200fg10000d6a4i57og65mkjkcdpu0.MP4` |
| middle | 59.7 | 初级 | 38.1 | 43.5 | 28.8 | 58.2 | 72.8 | 0 | `video/middle/v0300fg10000d4oq6avog65ihr8qf550.MP4` |
| middle | 62.6 | 中级 | 47.3 |  |  | 21.3 | 100 | 100 | `video/middle/v0300fg10000d5h313fog65nermuqklg.MP4` |
| middle | 62.2 | 中级 | 37.4 |  |  | 100 | 100 | 100 | `video/middle/v0300fg10000d6fe0nnog65jmdun29vg.MP4` |
| middle | 71.4 | 中级 | 55.7 | 16.3 | 63.9 | 63.4 | 100 | 0 | `video/middle/v0d00fg10000cu3omkvog65r22seg0t0.MP4` |
| middle | 59.7 | 初级 | 44.5 |  |  | 43.7 | 100 | 0 | `video/middle/v1e00fgi0000d5bksdfog65irrhr4bog.MP4` |
| middle | 61.8 | 中级 | 53.7 | 54.4 | 33.4 | 24.5 | 6 | 0 | `video/middle/v2800fgi0000d54jhefog65lbfdhma2g.MP4` |
| middle | 76.9 | 高级 | 60.4 | 28 | 46.5 | 57.3 | 100 | 0 | `video/middle/v2800fgi0000d5ehg1vog65tinkepgl0.MP4` |
