
import sys

content = open(sys.argv[1], "rb").read()

for c in content:
	print "%02x" % ord(c)


