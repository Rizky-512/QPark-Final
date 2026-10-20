"""Compatibility launcher: QPark now serves API and web together."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from server.app import main
if __name__=='__main__':sys.exit(main())
