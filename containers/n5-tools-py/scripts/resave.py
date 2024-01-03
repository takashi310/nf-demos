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

    usage_text = ("Usage:" + "  resave.py" + " [options]")
    parser = argparse.ArgumentParser(description=usage_text)
    parser.add_argument("-i", "--input", dest="input", type=str, default=None, help="input files")
    parser.add_argument("-o", "--output", dest="output", type=str, default=None, help="output file path (.xml)")
    parser.add_argument("-j", "--imagej", dest="imagej", type=str, default=None, help="path to imagej")
    parser.add_argument("-t", "--thread", dest="thread", type=int, default=0, help="number of threads")
    parser.add_argument("--verbose", dest="verbose", default=False, action="store_true", help="enable verbose logging")

    if not argv:
        parser.print_help()
        exit()

    args = parser.parse_args(argv)

    if args.verbose:
        logging.basicConfig(level=logging.INFO)

    input = args.input
    output = args.output
    threadnum = args.thread
    ij = "/nrs/scicompsoft/kawaset/Liu/Fiji.app/ImageJ-linux64"
    if args.imagej is not None:
        ij = args.imagej

    macro_dir = os.path.dirname(os.path.realpath(__file__))
    print(macro_dir)

    dataname = os.path.basename(output)
    stem = os.path.splitext(dataname)[0]
    outdirpath = os.path.dirname(output) + os.path.sep + stem + ".n5"

    ijargs2 = "select=" + input + " resave_angle=[All angles] resave_channel=[All channels] resave_illumination=[All illuminations] resave_tile=[All tiles] resave_timepoint=[All Timepoints] compression=Gzip subsampling_factors=[{ {1,1,1}, {2,2,1}, {4,4,2}, {8,8,4}, {16,16,8} }] n5_block_sizes=[{ {512,512,64}, {512,512,64}, {512,512,64}, {512,512,64}, {512,512,64} }] output_xml=" + output + " output_n5=" + outdirpath + " number_of_threads=" + str(threadnum)
    commands = []
    commands.append(f"{ij}")
    commands.append("--headless")
    commands.append("-macro")
    commands.append(os.path.join(macro_dir, "run_resave.ijm"))
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
