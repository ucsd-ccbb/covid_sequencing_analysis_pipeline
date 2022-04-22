import os
from hashlib import md5
from sys import argv


def generate_input_checksums(workspace_fp):
    result = {}

    for base_fp, _, fnames in os.walk(workspace_fp):
        for curr_fname in fnames:
            if curr_fname.startswith("."):
                continue

            fpath = os.path.join(base_fp, curr_fname)
            with open(fpath, "rb") as f:
                filebytes = f.read()
                filehash = md5(filebytes)
                filehash_hex = filehash.hexdigest()
                if curr_fname in result:
                    raise ValueError(f"file name {curr_fname} "
                                     f"appears more than once")
                result[curr_fname] = filehash_hex

    return result


def generate_checksums_file(args_list):
    input_dir = args_list[1]
    output_fp = args_list[2]

    fname_and_checksum_dict = generate_input_checksums(input_dir)

    output_lines = ["file_name,md5_hex_checksum\n"]
    output_entries = [f"{n},{c}\n" for n, c in fname_and_checksum_dict.items()]
    output_lines.extend(output_entries)

    with open(output_fp, "w") as f:
        f.writelines(output_lines)


if __name__ == '__main__':
    generate_checksums_file(argv)
