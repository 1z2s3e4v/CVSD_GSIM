import os

one = '0001'
zero = '0000'

def gen_I_16x16(fileName):
	f = open(fileName,'w')
	for i in range(16):
		line = ''
		for j in range(16):
			if(i==j):
				line += one
			else:
				line += zero
			if(j!=15):
				line += '_'
		f.write(line + '\n')

# main
#gen_I_16x16('indata5.dat')
