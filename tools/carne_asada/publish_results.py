"""Publish derived experiment evidence only; never publish videos or pose data."""
import argparse
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--scope', type=Path,
                        help='Explicit archive/source inventory; never infer collection completeness from clip counts.')
    args = parser.parse_args()
    result = json.loads(args.input.read_text())
    assert result['format'] == 'gurr-experiment/1'
    assert result['confirmed_coach_marks'] == 0
    assert result['claimed_technique_improvement'] is False
    # Publish a known summary schema, never arbitrary fields from a private
    # analysis file. Per-frame coordinates and track-level records stay local.
    public_fields = ('format', 'date', 'experiment', 'clip_count', 'duration_s',
                     'sample_rate', 'sampled_frames', 'frames_with_people',
                     'frames_with_multiple_people', 'person_detections', 'pose_samples',
                     'pipeline_elapsed_s', 'named_athlete_profiles_built',
                     'confirmed_coach_marks', 'claimed_technique_improvement',
                     'events_are_candidate_passes', 'caveats', 'aggregate', 'clips')
    result = {key: result[key] for key in public_fields}
    result['corpus_scope'] = (json.loads(args.scope.read_text()) if args.scope else {
        'collection_complete': False,
        'scope': 'selected local inputs only; completeness of the source collection is unverified',
    })
    assert isinstance(result['pose_samples'], int)
    root = Path(__file__).resolve().parents[2]
    sources = ['tools/carne_asada/footage.py',
               'packages/analysis_engine/tool/gurr_experiment.dart',
               'packages/analysis_engine/lib/src/track_analysis.dart',
               'packages/analysis_engine/lib/src/carne.dart',
               'packages/analysis_engine/lib/src/scoring.dart',
               'apps/strathvision/assets/packs/timber.json']
    result['engine_sources_sha256'] = {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
                                       for name in sources}
    private_samples = sorted((args.input.parent / 'tracks').glob('*.json'))
    first = json.loads(private_samples[0].read_text())
    result['detector_sha256'] = first['detector_sha256']
    result['pose_sha256'] = first['pose_sha256']
    result['pipeline_sha256'] = first['pipeline_sha256']
    assert result['engine_sources_sha256']['tools/carne_asada/footage.py'] == result['pipeline_sha256']
    for path in private_samples:
        data = json.loads(path.read_text())
        for key in ('detector_sha256', 'pose_sha256', 'pipeline_sha256'):
            assert data[key] == result[key], f'Inconsistent provenance in {path}'
    text = json.dumps(result, indent=2, allow_nan=False) + '\n'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(text)
    print(f'Published {result["clip_count"]} clip summaries to {args.output}')


if __name__ == '__main__':
    main()
