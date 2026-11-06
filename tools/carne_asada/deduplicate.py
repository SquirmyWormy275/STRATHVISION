"""Keep one analysis input per video SHA-256 and retain duplicate source paths."""
import argparse
import json
from copy import deepcopy
from pathlib import Path


def deduplicate(manifest):
    result = deepcopy(manifest)
    groups = {}
    for clip in result['clips']:
        groups.setdefault(clip['sha256'], []).append(clip)
    unique, duplicates = [], []
    for sha, clips in groups.items():
        # Prefer the shorter original filename over a downloaded "(1)" copy.
        clips.sort(key=lambda c: (len(c['relative_path']), c['relative_path']))
        first = clips[0]
        for clip in clips[1:]:
            for field in ('bytes', 'duration_s', 'fps', 'width', 'height',
                          'rotation', 'event_id', 'assignments'):
                if clip.get(field) != first.get(field):
                    raise ValueError(f'Conflicting {field} for identical content: {sha}')
            duplicates.append({'relative_path': clip['relative_path'], 'sha256': sha,
                               'duplicate_of': first['relative_path']})
        unique.append(first)
    result['source_video_file_count'] = len(result['clips'])
    result['clips'] = sorted(unique, key=lambda c: c['relative_path'])
    for index, clip in enumerate(result['clips'], 1):
        clip['index'] = index
    result['unique_video_count'] = len(unique)
    result['duplicate_files'] = duplicates
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = deduplicate(json.loads(args.source.read_text()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n')
    print(f"{result['source_video_file_count']} video files; "
          f"{result['unique_video_count']} unique; "
          f"{len(result['duplicate_files'])} duplicates excluded")


if __name__ == '__main__':
    main()
