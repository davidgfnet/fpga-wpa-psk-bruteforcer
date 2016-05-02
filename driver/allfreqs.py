
freqs = set()

base_freq = 100.0
#base_freq = 50.0
#base_freq = 25.0

min_M = int(400 / base_freq)
max_M = int(1000 / base_freq)

for M in range(min_M, max_M):
	for D in range(1,M*30):
		f = base_freq * M / D

		if (f <= 210 and f >= 50):
			freqs.add(f)

import pprint
pprint.pprint(sorted(list(freqs)))

