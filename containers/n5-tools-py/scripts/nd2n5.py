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
import skimage

import zarr
import tifffile

import dask
from distributed import LocalCluster, Client, Variable

import json

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

    usage_text = ("Usage:" + "  nd2n5.py" + " [options]")
    parser = argparse.ArgumentParser(description=usage_text)
    parser.add_argument("-i", "--input", dest="input", type=str, default=None, help="input files")
    parser.add_argument("-o", "--output", dest="output", type=str, default=None, help="output file path (.xml)")
    parser.add_argument("-t", "--thread", dest="thread", type=int, default=0, help="number of threads")
    parser.add_argument("-j", "--imagej", dest="imagej", type=str, default=None, help="path to imagej")
    parser.add_argument("-b", "--bg", dest="bg", type=str, default=None, help="path to a background image")
    parser.add_argument("-s", "--skip", dest="skip", type=int, default=-1, help="skip")
    parser.add_argument("--verbose", dest="verbose", default=False, action="store_true", help="enable verbose logging")

    if not argv:
        parser.print_help()
        exit()

    args = parser.parse_args(argv)

    if args.verbose:
        logging.basicConfig(level=logging.INFO)

    input = args.input.split(",")
    output = args.output.split(",")
    threadnum = args.thread
    bg = args.bg
    ij = args.imagej
    skip_stage = args.skip

    macro_dir = os.path.dirname(os.path.realpath(__file__))
    print(macro_dir)

    path_to_base_xml = ""
    dims = []

    for i in range(0, len(input)):
        dataname = os.path.basename(output[i])
        outdirpath = os.path.dirname(output[i])
        stem = os.path.splitext(dataname)[0]
        path_to_fixed_data = outdirpath + os.path.sep + stem + "_fixed.xml"
        if i == 0:
            path_to_base_xml = path_to_fixed_data

        if i <= skip_stage:
            continue

        imagej_arg = "define_dataset=[Automatic Loader (Bioformats based)] project_filename=" + dataname + " path=" + input[i] + " exclude=10 bioformats_series_are?=Tiles bioformats_channels_are?=Channels move_tiles_to_grid_(per_angle)?=[Do not move Tiles to Grid (use Metadata if available)] how_to_load_images=[Re-save as multiresolution N5] load_raw_data_virtually dataset_save_path=" + outdirpath + " compression=Gzip subsampling_factors=[{ {1,1,1} }] n5_block_sizes=[{ {2304,2304,1} }] number_of_threads=" + str(threadnum)

        commands = []
        commands.append(f"{ij}")
        commands.append("--headless")
        commands.append("-macro")
        commands.append(os.path.join(macro_dir, "run_bs.ijm"))
        commands.append(imagej_arg)

        print("running imagej...")
        logging.info(commands)
        print(execute(
            commands,
            lambda x: print("%s" % x, end=''),
            lambda x: print("%s" % x, end=''),
        ))

        xml = ET.parse(output[i])
        for item in xml.findall(".//ViewTransform"):
            name = item.find("./Name").text
            if name == "Translation":
                str_mat = item.find("affine")
                print(str_mat.text)
                mat_str_array = str_mat.text.split(" ")
                out_str_mat = ""
                count = 0
                for elem in mat_str_array:
                    if count == 7:
                        fval = float(elem)
                        fval *= -1.0
                        out_str_mat += " " + str(fval)
                    else:
                        if count > 0:
                            out_str_mat += " "
                        out_str_mat += elem
                    count += 1
                print(out_str_mat)
                str_mat.text = out_str_mat

        xml.write(path_to_fixed_data)

        if bg:
            base_path = os.path.join(outdirpath, stem + ".n5")
            bg_array = tifffile.imread(bg, is_shaped=False)
            print(bg_array.shape)

            group_paths = []
            for item in xml.findall(".//ViewRegistration"):
                setup = item.attrib['setup']
                timepoint = item.attrib['timepoint']
                group_path = 'setup' + setup + "/" + 'timepoint' + timepoint + '/s0'
                group_paths.append(group_path)

            n5input = zarr.open(store=zarr.N5Store(base_path), mode='a')
            #n5input.visititems(print_visitor)

            cluster = LocalCluster(n_workers=threadnum, threads_per_worker=1)
            client = Client(cluster, asynchronous=True)
            for g in group_paths:
                print(n5input[g])
                futures = []
                n5array = n5input[g]
                depth = n5array.shape[0]
                for z in range(depth):
                    future = dask.delayed(subtract_background)(n5array, bg_array, z)
                    futures.append(future)
                dask.compute(futures)
            client.close()
            cluster.close()
        
        path_to_fused_data = outdirpath + os.path.sep + stem + "_fused_tmp.n5"
        path_to_fused_data_xml = outdirpath + os.path.sep + stem + "_fused_tmp-n5.xml"
        path_to_fused_tiff_xml = outdirpath + os.path.sep + stem + "_fused_tmp-tif.xml"
        path_to_final_fused_data = outdirpath + os.path.sep + stem + "_fused.n5"
        path_to_final_fused_data_xml = outdirpath + os.path.sep + stem + "_fused-n5.xml"

        path_to_fused_n5_s0_json = path_to_fused_data + os.path.sep + "setup0" + os.path.sep + "timepoint0" + os.path.sep + "s0" + os.path.sep + "attributes.json"

        if i == 0:
            ijargs2 = "select=" + path_to_fixed_data + " process_angle=[All angles] process_channel=[All channels] process_illumination=[All illuminations] process_tile=[All tiles] process_timepoint=[All Timepoints] method=[Phase Correlation] downsample_in_x=64 downsample_in_y=64 downsample_in_z=1"
            ijargs2 += ";"
            ijargs2 += "select=" + path_to_fixed_data + " filter_by_link_quality min_r=0.1 max_r=1 filter_by_shift_in_each_dimension max_shift_in_x=100 max_shift_in_y=100 max_shift_in_z=100 max_displacement=0"
            ijargs2 += ";"
            ijargs2 += "select=" + path_to_fixed_data + " process_angle=[All angles] process_channel=[All channels] process_illumination=[All illuminations] process_tile=[All tiles] process_timepoint=[All Timepoints] relative=2.500 absolute=3.500 global_optimization_strategy=[Two-Round using Metadata to align unconnected Tiles and iterative dropping of bad links] fix_group_0-0"
            ijargs2 += ";"
            ijargs2 += "select=" + path_to_fixed_data +  " process_angle=[All angles] process_channel=[All channels] process_illumination=[All illuminations] process_tile=[All tiles] process_timepoint=[All Timepoints] icp_refinement_type=[Simple (tile registration)] downsampling=[Downsampling 8/8/4] interest=[Average Threshold] icp_max_error=[Normal Adjustment (<5px)]"
            ijargs2 += ";"
            ijargs2 += "select=" + path_to_fixed_data + " process_angle=[All angles] process_channel=[All channels] process_illumination=[All illuminations] process_tile=[All tiles] process_timepoint=[All Timepoints] bounding_box=[Currently Selected Views] downsampling=1 interpolation=[Linear Interpolation] pixel_type=[16-bit unsigned integer] interest_points_for_non_rigid=[-= Disable Non-Rigid =-] blend produce=[Each timepoint & channel] fused_image=[ZARR/N5/HDF5 export using N5-API] define_input=[Auto-load from input data (values shown below)] export=N5 create n5_dataset_path=" + path_to_fused_data + " xml_output_file=" + path_to_fused_data_xml + " viewid_timepointid=0 viewid_setupid=0 show_advanced_block_size_options block_size_x=512 block_size_y=512 block_size_z=64 block_size_factor_x=1 block_size_factor_y=1 block_size_factor_z=1 subsampling_factors=[{ {1,1,1} }]"
            commands = []
            commands.append(f"{ij}")
            commands.append("--headless")
            commands.append("-macro")
            commands.append(os.path.join(macro_dir, "run_stitch.ijm"))
            commands.append(ijargs2)

            print("running imagej...")
            logging.info(commands)
            print(execute(
                commands,
                lambda x: print("%s" % x, end=''),
                lambda x: print("%s" % x, end=''),
            ))

            with open(path_to_fused_n5_s0_json) as f:
                data = json.load(f)
                dims = data['dimensions']
                print(dims)

            ijargs2 = "select=" + path_to_fused_data_xml + " resave_angle=[All angles] resave_channel=[All channels] resave_illumination=[All illuminations] resave_tile=[All tiles] resave_timepoint=[All Timepoints] compression=Gzip subsampling_factors=[{ {1,1,1}, {2,2,1}, {4,4,2}, {8,8,4}, {16,16,8} }] n5_block_sizes=[{ {512,512,64}, {512,512,64}, {512,512,64}, {512,512,64}, {512,512,64} }] output_xml=" + path_to_final_fused_data_xml + " output_n5=" + path_to_final_fused_data + " number_of_threads=" + str(threadnum)
            ijargs2 += ";"
            ijargs2 += "select=" + path_to_fused_data_xml + " resave_angle=[All angles] resave_channel=[All channels] resave_illumination=[All illuminations] resave_tile=[All tiles] resave_timepoint=[All Timepoints] export_path=" + path_to_fused_tiff_xml
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

#            xml = ET.parse(path_to_fused_tiff_xml)
#            for item in xml.findall(".//filePattern"):
#                tifpath = os.path.join(outdirpath, item.text)
#                newtifpath = os.path.join(outdirpath, stem + "_fused.tif")
#                os.rename(tifpath, newtifpath)
#                break

        else:
            xml_src = ET.parse(path_to_base_xml)
            xml = ET.parse(path_to_fixed_data)
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
            
            path_to_fixed_data2 = outdirpath + os.path.sep + stem + "_fixed_tmp.xml"
            xml.write(path_to_fixed_data2)

            ijargs2 = "select=" + path_to_fixed_data2 + " process_angle=[All angles] process_channel=[All channels] process_illumination=[All illuminations] process_tile=[All tiles] process_timepoint=[All Timepoints] bounding_box=[Currently Selected Views] downsampling=1 interpolation=[Linear Interpolation] pixel_type=[16-bit unsigned integer] interest_points_for_non_rigid=[-= Disable Non-Rigid =-] non_rigid_advanced_parameters blend produce=[Each timepoint & channel] fused_image=[ZARR/N5/HDF5 export using N5-API] define_input=[Auto-load from input data (values shown below)] export=N5 create n5_dataset_path=" + path_to_fused_data + " xml_output_file=" + path_to_fused_data_xml + " viewid_timepointid=0 viewid_setupid=0 show_advanced_block_size_options block_size_x=512 block_size_y=512 block_size_z=64 block_size_factor_x=1 block_size_factor_y=1 block_size_factor_z=1 subsampling_factors=[{ {1,1,1} }]"
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

            with open(path_to_fused_n5_s0_json, 'r+') as f:
                data = json.load(f)
                data['dimensions'] = dims
                f.seek(0)
                json.dump(data, f, indent=4)
                f.truncate()

            ijargs2 = "select=" + path_to_fused_data_xml + " resave_angle=[All angles] resave_channel=[All channels] resave_illumination=[All illuminations] resave_tile=[All tiles] resave_timepoint=[All Timepoints] compression=Gzip subsampling_factors=[{ {1,1,1}, {2,2,1}, {4,4,2}, {8,8,4}, {16,16,8} }] n5_block_sizes=[{ {512,512,64}, {512,512,64}, {512,512,64}, {512,512,64}, {512,512,64} }] output_xml=" + path_to_final_fused_data_xml + " output_n5=" + path_to_final_fused_data + " number_of_threads=" + str(threadnum)
            ijargs2 += ";"
            ijargs2 += "select=" + path_to_fused_data_xml + " resave_angle=[All angles] resave_channel=[All channels] resave_illumination=[All illuminations] resave_tile=[All tiles] resave_timepoint=[All Timepoints] export_path=" + path_to_fused_tiff_xml
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

#            xml = ET.parse(path_to_fused_tiff_xml)
#            for item in xml.findall(".//filePattern"):
#                tifpath = os.path.join(outdirpath, item.text)
#                newtifpath = os.path.join(outdirpath, stem + "_fused.tif")
#                os.rename(tifpath, newtifpath)
#                break

    


if __name__ == '__main__':
    main()
