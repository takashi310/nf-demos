import glob
import os
import sys
import re
import argparse
import platform
import shutil

import subprocess

import logging

import asyncio

import xml.etree.ElementTree as ET
import copy

import json

def main():

    argv = sys.argv
    argv = argv[1:]

    usage_text = ("Usage:" + "  combine_n5.py" + " [options]")
    parser = argparse.ArgumentParser(description=usage_text)
    parser.add_argument("-i", "--input", dest="input", type=str, default=None, help="input dirs (BDV N5)")
    parser.add_argument("-o", "--output", dest="output", type=str, default=None, help="output file dir")
    parser.add_argument("-c", "--cid", dest="cid", type=int, default=0, help="channel id")
    parser.add_argument("--attr", dest="attr", default=False, action="store_true", help="copy attributes")
    parser.add_argument("--verbose", dest="verbose", default=False, action="store_true", help="enable verbose logging")

    if not argv:
        parser.print_help()
        exit()

    args = parser.parse_args(argv)

    if args.verbose:
        logging.basicConfig(level=logging.INFO)

    input = args.input.split(",")
    output = args.output
    cid = args.cid
    if not os.path.exists(output):
        os.makedirs(output)

    for i in range(0, len(input)):
        n5path = ""
        xml = ET.parse(input[i])
        for item in xml.findall(".//n5"):
            n5path = os.path.join(os.path.dirname(input[i]), item.text)

        if i == 0 and args.attr:
            shutil.copyfile(os.path.join(n5path, "attributes.json"), os.path.join(output, "attributes.json"))

        chdir = os.path.join(output, "c" + str(cid + i))
        if not os.path.exists(chdir):
            src = os.path.join(os.path.join(n5path, "setup0"), "timepoint0")
            shutil.move(src, chdir)


if __name__ == '__main__':
    main()
