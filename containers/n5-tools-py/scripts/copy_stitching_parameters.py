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

    usage_text = ("Usage:" + "  copy_stitcher_settings.py" + " [options]")
    parser = argparse.ArgumentParser(description=usage_text)
    parser.add_argument("-i", "--input", dest="input", type=str, default=None, help="input files")
    parser.add_argument("-t", "--target", dest="target", type=str, default=None, help="target file path (.xml)")
    parser.add_argument("-o", "--output", dest="output", type=str, default=None, help="output file path (.xml)")
    parser.add_argument("--verbose", dest="verbose", default=False, action="store_true", help="enable verbose logging")

    if not argv:
        parser.print_help()
        exit()

    args = parser.parse_args(argv)

    if args.verbose:
        logging.basicConfig(level=logging.INFO)

    input = args.input.split(",")
    target = args.target.split(",")
    output = args.output.split(",")
    
    path_to_base_xml = ""
    dims = []

    for i in range(0, len(target)):
        dataname = os.path.basename(target[i])
        outdirpath = os.path.dirname(target[i])
        stem = os.path.splitext(dataname)[0]
        path_to_base_xml = input[0]

        xml_src = ET.parse(path_to_base_xml)
        xml = ET.parse(target[i])
        src_parent_map = {c:p for p in xml_src.getroot().iter() for c in p}
        dst_parent_map = {c:p for p in xml.getroot().iter() for c in p}
            
        elem_src = None
        for item in xml_src.findall(".//StitchingResults"):
            elem_src = copy.deepcopy(item)
            break
        for item in xml.findall(".//StitchingResults"):
            parent = dst_parent_map[item]
            parent_index = list(parent).index(item)
            parent.remove(item)
            parent.insert(parent_index, elem_src)
            break
            
        elem_src = None
        for item in xml_src.findall(".//ViewInterestPoints"):
            elem_src = copy.deepcopy(item)
            break
        for item in xml.findall(".//ViewInterestPoints"):
            parent = dst_parent_map[item]
            parent_index = list(parent).index(item)
            parent.remove(item)
            parent.insert(parent_index, elem_src)
            break

        for item in xml_src.findall(".//ViewTransform"):
            name = item.find("./Name").text
            if name == "Stitching Transform":
                copied_item = copy.deepcopy(item)
                parent = src_parent_map[item]
                setupnum = parent.attrib["setup"]
                for dstitem in xml.findall(".//ViewRegistration"):
                    dstsetupnum = dstitem.attrib["setup"]
                    print(dstsetupnum)
                    if dstsetupnum == setupnum:
                        print("insert")
                        dstitem.insert(0, copied_item)
            
        for item in xml_src.findall(".//ViewTransform"):
            name = item.find("./Name").text
            if name == "Tile ICP Refinement":
                copied_item = copy.deepcopy(item)
                parent = src_parent_map[item]
                setupnum = parent.attrib["setup"]
                for dstitem in xml.findall(".//ViewRegistration"):
                    dstsetupnum = dstitem.attrib["setup"]
                    print(dstsetupnum)
                    if dstsetupnum == setupnum:
                        print("insert")
                        dstitem.insert(0, copied_item)
                        
        xml.write(output[i])

    


if __name__ == '__main__':
    main()
