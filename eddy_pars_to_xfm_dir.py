#!/usr/bin/python

import scipy as sp
import scipy.linalg as la
from numpy import loadtxt
import sys
import os

outdir=sys.argv[2]

parFileName=sys.argv[1]

if not os.path.exists(outdir):
    os.makedirs(outdir)

i=0
with open(parFileName,"r") as ifile:
    for line in ifile:
        #print line
        numeric_array=map(float,line.split())

        Xtrans=numeric_array[0]
        Ytrans=numeric_array[1]
        Ztrans=numeric_array[2]
        Xrot=numeric_array[3]
        Yrot=numeric_array[4]
        Zrot=numeric_array[5]

        Rx=sp.array([[1,            0,              0],
                     [0, sp.cos(Xrot),  -sp.sin(Xrot)],
                     [0, sp.sin(Xrot),  sp.cos(Xrot)]])

        Ry=sp.array([[ sp.cos(Yrot), 0,  sp.sin(Yrot)],
                     [            0, 1,             0],
                     [-sp.sin(Yrot), 0, sp.cos(Xrot)]])

        Rz=sp.array([[sp.cos(Zrot), -sp.sin(Zrot),  0],
                     [sp.sin(Zrot),  sp.cos(Zrot),  0],
                     [           0,             0,  1]])

        R=la.inv(Rx.dot(Ry.dot(Rz)))

        ofile=open(outdir + "/MAT_" + "{0:0>4}".format(i),"w")

        #print R[0,0],R[0,1],R[0,2],Xtrans
        #print R[1,0],R[1,1],R[1,2],Ytrans
        #print R[2,0],R[2,1],R[2,2],Ztrans
        #print 0,0,0,1

        oline1="{0:.6f}".format(R[0,0]) + " " + "{0:.6f}".format(R[0,1])+ " " + "{0:.6f}".format(R[0,2])+ " " + "{0:.6f}".format(Xtrans)+"\n"
        oline2="{0:.6f}".format(R[1,0]) + " " + "{0:.6f}".format(R[1,1])+ " " + "{0:.6f}".format(R[1,2])+ " " + "{0:.6f}".format(Ytrans)+"\n"
        oline3="{0:.6f}".format(R[2,0]) + " " + "{0:.6f}".format(R[2,1])+ " " + "{0:.6f}".format(R[2,2])+ " " + "{0:.6f}".format(Ztrans)+"\n"
        oline4="0 0 0 1 \n"

        ofile.write(oline1)
        ofile.write(oline2)
        ofile.write(oline3)
        ofile.write(oline4)
        ofile.close()
        
        i += 1
