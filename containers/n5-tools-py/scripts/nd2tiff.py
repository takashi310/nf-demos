import os

import os
import sys
import re
import argparse

import nd2

import dask
import dask.array as da
import dask.bag as db
import dask.dataframe as dd
import zarr
import numpy as np

from dask.distributed import LocalCluster, Client

from dask.diagnostics import ProgressBar, Profiler, ResourceProfiler, CacheProfiler, visualize

from pathlib import Path

import tifffile

def convert_tile_nd2tiff(input, outdir, tile_id, ch_id, time_id):
    with nd2.ND2File(input) as nd2_file:
        print("#1")
        input_array = nd2_file.to_dask()
        d = input_array.shape[2]
        h = input_array.shape[4]
        w = input_array.shape[5]
        output = np.zeros((d, h, w), dtype=input_array.dtype)

        print("#2")
        output[:d, :h, :w] = input_array[time_id, tile_id, :d, ch_id, :h, :w]

        opath = os.path.join(outdir, "tiff_" + str(tile_id) + "_" + str(ch_id) + "_" + str(time_id) + ".tif")

        print("#3")
        tifffile.imsave(opath, output, compression=("ZLIB", 6))

        print("#4")

    return opath

def nd2tiff():

    argv = sys.argv
    argv = argv[1:]

    usage_text = ("Usage:" + "  nd2n5.py" + " [options]")
    parser = argparse.ArgumentParser(description=usage_text)
    parser.add_argument("-i", "--input", dest="input", type=str, default=None, help="input files")
    parser.add_argument("-o", "--output", dest="output", type=str, default=None, help="output file path (.xml)")
    parser.add_argument("-b", "--bg", dest="bg", type=str, default=None, help="background file path (.xml)")
    parser.add_argument("--verbose", dest="verbose", default=False, action="store_true", help="enable verbose logging")

    if not argv:
        parser.print_help()
        exit()

    args = parser.parse_args(argv)

    input = args.input
    outpath = args.output
    outdir = os.path.dirname(outpath)
    bg = args.bg

    numbers = re.findall(r'\d+', outpath)
    time_id = int(numbers[len(numbers)-1])
    ch_id = int(numbers[len(numbers)-2])
    tile_id = int(numbers[len(numbers)-3])
    print(time_id)
    print(ch_id)
    print(tile_id)

    Path(outdir).mkdir(parents=True, exist_ok=True)

    darray = nd2.imread(input, dask=True)

    print(darray.shape)

    timepoints = darray.shape[0]
    tiles = darray.shape[1]
    channels = darray.shape[3]

    d = darray.shape[2]
    h = darray.shape[4]
    w = darray.shape[5]

    bg_array = tifffile.imread(bg, is_shaped=False)

    output = np.zeros((d, h, w), dtype=darray.dtype)
    output[:d, :h, :w] = darray[time_id, tile_id, :d, ch_id, :h, :w]

    for z in range(d):
        n5slice = output[z, :, :]
        clipped = bg_array.clip(None, n5slice)
        output[z, :, :] = n5slice - clipped

    tifffile.imsave(outpath, output, compression=("ZLIB", 6))



def main():
    nd2tiff()

if __name__ == '__main__':
    main()
