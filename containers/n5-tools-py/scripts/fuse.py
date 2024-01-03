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


# https://kevinmccarthy.org/2016/07/25/streaming-subprocess-stdin-and-stdout-with-asyncio-in-python/
async def _read_stream(stream, cb):  
    while True:
        ch = await stream.read(1)
        if ch:
            try:
                cb(ch.decode("utf-8"))
            except UnicodeDecodeError:
                print(ch)
        else:
            break

async def _stream_subprocess(cmd, stdout_cb, stderr_cb):  
    process = await asyncio.create_subprocess_exec(*cmd,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)

    await asyncio.wait([
        asyncio.create_task(_read_stream(process.stdout, stdout_cb)),
        asyncio.create_task(_read_stream(process.stderr, stderr_cb))
    ])
    return await process.wait()

def execute(cmd, stdout_cb, stderr_cb):  
    loop = asyncio.new_event_loop()
    #asyncio.set_event_loop(loop)
    rc = loop.run_until_complete(
        _stream_subprocess(
            cmd,
            stdout_cb,
            stderr_cb,
    ))
    loop.close()
    return rc
##################

def main():

    argv = sys.argv
    argv = argv[1:]

    usage_text = ("Usage:" + "  fuse.py" + " [options]")
    parser = argparse.ArgumentParser(description=usage_text)
    parser.add_argument("-i", "--input", dest="input", type=str, default=None, help="input files")
    parser.add_argument("-o", "--output", dest="output", type=str, default=None, help="output file path (.xml)")
    parser.add_argument("-j", "--imagej", dest="imagej", type=str, default=None, help="path to imagej")
    parser.add_argument("--verbose", dest="verbose", default=False, action="store_true", help="enable verbose logging")

    if not argv:
        parser.print_help()
        exit()

    args = parser.parse_args(argv)

    if args.verbose:
        logging.basicConfig(level=logging.INFO)

    input = args.input
    output = args.output
    ij = "/nrs/scicompsoft/kawaset/Liu/Fiji.app/ImageJ-linux64"
    if args.imagej is not None:
        ij = args.imagej

    macro_dir = os.path.dirname(os.path.realpath(__file__))
    print(macro_dir)

    dataname = os.path.basename(output)
    stem = os.path.splitext(dataname)[0]
    outdirpath = os.path.dirname(output) + os.path.sep + stem + ".n5"

    ijargs2 = "select=" + input + " process_angle=[All angles] process_channel=[All channels] process_illumination=[All illuminations] process_tile=[All tiles] process_timepoint=[All Timepoints] bounding_box=[Currently Selected Views] downsampling=1 interpolation=[Linear Interpolation] pixel_type=[16-bit unsigned integer] interest_points_for_non_rigid=[-= Disable Non-Rigid =-] non_rigid_advanced_parameters blend produce=[Each timepoint & channel] fused_image=[ZARR/N5/HDF5 export using N5-API] define_input=[Auto-load from input data (values shown below)] export=N5 create n5_dataset_path=" + outdirpath + " xml_output_file=" + output + " viewid_timepointid=0 viewid_setupid=0 show_advanced_block_size_options block_size_x=512 block_size_y=512 block_size_z=64 block_size_factor_x=1 block_size_factor_y=1 block_size_factor_z=1 subsampling_factors=[{ {1,1,1}, {2,2,1}, {4,4,2}, {8,8,4}, {16,16,8} }] "
    commands = []
    commands.append(f"{ij}")
    commands.append("--headless")
    commands.append("-macro")
    commands.append(os.path.join(macro_dir, "run_fuse.ijm"))
    commands.append(ijargs2)

    print("running imagej...")
    logging.info(commands)
    print(execute(
        commands,
        lambda x: print("%s" % x, end=''),
        lambda x: print("%s" % x, end=''),
    ))

if __name__ == '__main__':
    main()
