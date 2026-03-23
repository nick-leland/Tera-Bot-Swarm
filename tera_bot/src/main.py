# This will be the primary setup and order for the bot's backend.  This is the main file that will be used to run the bot.
import random
from wonderwords import RandomWord


def generate_account_information():
    pass


def choose_class(account_classes: list[str] | None = None) -> str:
    """
    Choose a class for the character based on classes not already in the account.
    """
    potential_classes = [
        "warrior", "mystic", "lancer",
        "reaper", "slayer", "gunner",
        "berserker", "brawler", "sorcerer",
        "ninja", "archer", "valkyrie",
        "priest",
    ]
    if account_classes is None:
        return random.choice(potential_classes)
    return random.choice(list(set(potential_classes) - set(account_classes)))


def choose_race(current_class: str) -> str:
    """
    Choose a race for the character based on the class.
    """
    exclusive_race_dict = {
        "reaper": ["elin"],
        "gunner": ["castanic", "high elf", "elin"],
        "brawler": ["human", "elin", "popori"],
        "ninja": ["elin"],
        "valkyrie": ["castanic", "elin"]
    }
    race_list = ["human", "castanic", "aman", "high elf", "popori", "elin", "baraka"]
    gender_dict = {
        "human": ["male", "female"],
        "castanic": ["male", "female"],
        "aman": ["male", "female"],
        "high elf": ["male", "female"],
    }
    
    if current_class not in exclusive_race_dict:
        race = random.choice(race_list)
    else:
        race = random.choice(exclusive_race_dict[current_class])

    if race in gender_dict:
        gender = random.choice(gender_dict[race])
        return [race, gender]
    else:
        return [race]


def make_character():
    char_class = choose_class()
    race_results = choose_race(char_class)
    if len(race_results) == 2:
        char_race, char_gender = race_results
    else:
        char_race = race_results[0]
        char_gender = None
    return [char_class, char_race, char_gender]


NUM_OF_CHARACTERS = 0
MAX_CHARACTER = 8

if __name__ == "__main__":
    char_name = RandomWord().word()
    char_class, char_race, char_gender = make_character()
    print(f"Name: {char_name}")
    print(f"Class: {char_class}")
    print(f"Race: {char_race}")
    print(f"Gender: {char_gender}")
