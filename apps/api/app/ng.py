"""Nigeria's 36 states and the FCT, spelled one way everywhere.

Emergency numbers reach an estate by its state and LGA, matched exactly (see the directory RLS
policy in migration 0001), so a state typed two ways would silently cut an estate off from its
state numbers. The dashboard offers this list; the API accepts nothing else for an estate.
"""

from typing import Literal, get_args

NgState = Literal[
    "Abia", "Adamawa", "Akwa Ibom", "Anambra", "Bauchi", "Bayelsa", "Benue", "Borno", "Cross River", "Delta",
    "Ebonyi", "Edo", "Ekiti", "Enugu", "FCT", "Gombe", "Imo", "Jigawa", "Kaduna", "Kano", "Katsina", "Kebbi",
    "Kogi", "Kwara", "Lagos", "Nasarawa", "Niger", "Ogun", "Ondo", "Osun", "Oyo", "Plateau", "Rivers", "Sokoto",
    "Taraba", "Yobe", "Zamfara",
]
STATES: tuple[str, ...] = get_args(NgState)
