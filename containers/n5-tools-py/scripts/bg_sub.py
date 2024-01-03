import glob
import os
import sys
import re
import argparse
import platform

import subprocess

import logging

import asyncio

import xml.etree.ElementTree as ET
import copy

import numpy as np
import zarr
import tifffile

import dask
from distributed import LocalCluster, Client, Variable

import json

def print_visitor(name, obj):
    print((name, obj))

def subtract_background(n5array, bg_array, z):
    n5slice = n5array[z, :, :]
    clipped = bg_array.clip(None, n5slice)
    n5array[z, :, :] = n5slice - clipped
    print("z " + str(z) + " subtracted")

def main():

    argv = sys.argv
    argv = argv[1:]

    usage_text = ("Usage:" + "  bg_sub.py" + " [options]")
    parser = argparse.ArgumentParser(description=usage_text)
    parser.add_argument("-i", "--input", dest="input", type=str, default=None, help="input file path (.xml)")
    parser.add_argument("-t", "--thread", dest="thread", type=int, default=1, help="number of threads")
    parser.add_argument("-b", "--bg", dest="bg", type=str, default=None, help="path to a background image")
    parser.add_argument("--verbose", dest="verbose", default=False, action="store_true", help="enable verbose logging")

    if not argv:
        parser.print_help()
        exit()

    args = parser.parse_args(argv)

    if args.verbose:
        logging.basicConfig(level=logging.INFO)

    input = args.input.split(",")
    threadnum = args.thread
    bg = args.bg

    macro_dir = os.path.dirname(os.path.realpath(__file__))
    print(macro_dir)


    for i in range(0, len(input)):
        group_paths = []

        n5path = ""
        xml = ET.parse(input[i])
        for item in xml.findall(".//n5"):
            n5path = os.path.join(os.path.dirname(input[i]), item.text)
        
        if bg:
            bg_array = tifffile.imread(bg, is_shaped=False)
            print(bg_array.shape)

            for item in xml.findall(".//ViewRegistration"):
                setup = item.attrib['setup']
                timepoint = item.attrib['timepoint']
                group_path = 'setup' + setup + "/" + 'timepoint' + timepoint + '/s0'
                group_paths.append(group_path)

            n5input = zarr.open(store=zarr.N5Store(n5path), mode='a')
            #n5input.visititems(print_visitor)

            cluster = LocalCluster(n_workers=threadnum, threads_per_worker=1)
            client = Client(cluster, asynchronous=True)
            for g in group_paths:
                #print(n5input[g])
                futures = []
                n5array = n5input.get(g, None)
                if n5array != None:
                    depth = n5array.shape[0]
                    for z in range(depth):
                        future = dask.delayed(subtract_background)(n5array, bg_array, z)
                        futures.append(future)
                    dask.compute(futures)
            client.close()
            cluster.close()


if __name__ == '__main__':
    main()
