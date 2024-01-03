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

import json

def main():

    argv = sys.argv
    argv = argv[1:]

    usage_text = ("Usage:" + "  copy_dims.py" + " [options]")
    parser = argparse.ArgumentParser(description=usage_text)
    parser.add_argument("-i", "--input", dest="input", type=str, default=None, help="input files")
    parser.add_argument("-t", "--target", dest="target", type=str, default=None, help="target file path (.xml)")
    parser.add_argument("--verbose", dest="verbose", default=False, action="store_true", help="enable verbose logging")

    if not argv:
        parser.print_help()
        exit()

    args = parser.parse_args(argv)

    if args.verbose:
        logging.basicConfig(level=logging.INFO)

    input = args.input.split(",")
    output = args.target.split(",")
    
    path_to_base_xml = ""
    dims = []

    n5path = ""
    xml = ET.parse(input[0])
    for item in xml.findall(".//n5"):
        n5path = os.path.join(os.path.dirname(input[0]), item.text)  
    path_to_fused_n5_s0_json = n5path + os.path.sep + "setup0" + os.path.sep + "timepoint0" + os.path.sep + "s0" + os.path.sep + "attributes.json"
    with open(path_to_fused_n5_s0_json) as f:
        data = json.load(f)
        dims = data['dimensions']
        print(dims)

    for i in range(0, len(output)):
        n5path = ""
        xml = ET.parse(output[0])
        for item in xml.findall(".//n5"):
            n5path = os.path.join(os.path.dirname(output[i]), item.text)  
        path_to_fused_n5_s0_json = n5path + os.path.sep + "setup0" + os.path.sep + "timepoint0" + os.path.sep + "s0" + os.path.sep + "attributes.json"
        with open(path_to_fused_n5_s0_json, 'r+') as f:
            data = json.load(f)
            data['dimensions'] = dims
            f.seek(0)
            json.dump(data, f, indent=4)
            f.truncate()

    


if __name__ == '__main__':
    main()
