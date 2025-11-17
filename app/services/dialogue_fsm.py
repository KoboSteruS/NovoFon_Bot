"""
Finite State Machine (FSM) for dialogue management
"""
import enum
from typing import Optional, Dict, Any, Callable
from loguru import logger
from dataclasses import dataclass


class DialogueState(str, enum.Enum):
    """Dialogue states"""
    GREETING = "greeting"
    INTRO = "intro"
    OFFER = "offer"
    CLARIFICATION = "clarification"
    OBJECTION_HANDLING = "objection_handling"
    AGREEMENT = "agreement"
    DETAILS = "details"
    CONFIRMATION = "confirmation"
    FINAL = "final"
    GOODBYE = "goodbye"
    END = "end"


class Intent(str, enum.Enum):
    """User intents"""
    POSITIVE = "positive"  # Да, согласен, хорошо
    NEGATIVE = "negative"  # Нет, не хочу, не интересно
    QUESTION = "question"  # Что? Как? Почему?
    CLARIFICATION = "clarification"  # Уточняющий вопрос
    OBJECTION = "objection"  # Возражение
    OFFENSIVE = "offensive"  # Нецензурная лексика
    SILENCE = "silence"  # Тишина
    UNKNOWN = "unknown"  # Не распознано


@dataclass
class DialogueContext:
    """Context for dialogue"""
    user_name: Optional[str] = None
    phone: Optional[str] = None
    offer_accepted: bool = False
    objections_count: int = 0
    silence_count: int = 0
    custom_data: Dict[str, Any] = None
    
    def __post_init__(self):
        if self.custom_data is None:
            self.custom_data = {}


class DialogueFSM:
    """
    Finite State Machine for managing dialogue flow
    """
    
    def __init__(self):
        """Initialize FSM"""
        self.state = DialogueState.GREETING
        self.context = DialogueContext()
        self.history: list[tuple[DialogueState, str]] = []
        
        # Callbacks
        self.on_state_change: Optional[Callable] = None
        
        logger.info("Dialogue FSM initialized")
    
    def reset(self):
        """Reset FSM to initial state"""
        self.state = DialogueState.GREETING
        self.context = DialogueContext()
        self.history = []
        logger.info("FSM reset")
    
    def _transition(self, new_state: DialogueState, reason: str = ""):
        """
        Transition to new state
        
        Args:
            new_state: Target state
            reason: Reason for transition
        """
        old_state = self.state
        self.state = new_state
        self.history.append((new_state, reason))
        
        logger.info(f"State transition: {old_state} -> {new_state} ({reason})")
        
        if self.on_state_change:
            self.on_state_change(old_state, new_state, reason)
    
    def process_user_input(self, text: str, intent: Optional[Intent] = None) -> str:
        """
        Process user input and generate response
        
        Args:
            text: User's input text
            intent: Detected intent (optional, will be detected if not provided)
        
        Returns:
            Bot's response text
        """
        # Detect intent if not provided
        if intent is None:
            intent = self._detect_intent(text)
        
        logger.info(f"Processing input in state {self.state}, intent: {intent}")
        
        # Handle offensive language immediately
        if intent == Intent.OFFENSIVE:
            self._transition(DialogueState.END, "offensive language")
            return "Извините, я вынужден завершить разговор. До свидания."
        
        # Handle silence
        if intent == Intent.SILENCE:
            self.context.silence_count += 1
            if self.context.silence_count >= 3:
                self._transition(DialogueState.END, "too much silence")
                return "Похоже, связь прервалась. Перезвоним позже. До свидания."
            return self._get_repeat_message()
        
        # Reset silence counter on successful input
        self.context.silence_count = 0
        
        # Process based on current state
        if self.state == DialogueState.GREETING:
            return self._handle_greeting(text, intent)
        
        elif self.state == DialogueState.INTRO:
            return self._handle_intro(text, intent)
        
        elif self.state == DialogueState.OFFER:
            return self._handle_offer(text, intent)
        
        elif self.state == DialogueState.CLARIFICATION:
            return self._handle_clarification(text, intent)
        
        elif self.state == DialogueState.OBJECTION_HANDLING:
            return self._handle_objection(text, intent)
        
        elif self.state == DialogueState.AGREEMENT:
            return self._handle_agreement(text, intent)
        
        elif self.state == DialogueState.DETAILS:
            return self._handle_details(text, intent)
        
        elif self.state == DialogueState.CONFIRMATION:
            return self._handle_confirmation(text, intent)
        
        elif self.state == DialogueState.FINAL:
            return self._handle_final(text, intent)
        
        elif self.state == DialogueState.GOODBYE:
            self._transition(DialogueState.END, "goodbye complete")
            return ""
        
        else:
            return "Извините, произошла ошибка. До свидания."
    
    def _detect_intent(self, text: str) -> Intent:
        """
        Detect user intent from text
        
        Args:
            text: User's input
        
        Returns:
            Detected intent
        """
        text_lower = text.lower().strip()
        
        # Check for silence (empty or very short)
        if len(text_lower) < 2:
            return Intent.SILENCE
        
        # Check for offensive language
        offensive_words = ['блять', 'хуй', 'пизд', 'ебать', 'сука']
        if any(word in text_lower for word in offensive_words):
            return Intent.OFFENSIVE
        
        # Check for positive responses
        positive_words = ['да', 'хорошо', 'ладно', 'согласен', 'принято', 'интересно', 'давайте']
        if any(word in text_lower for word in positive_words):
            return Intent.POSITIVE
        
        # Check for negative responses
        negative_words = ['нет', 'не хочу', 'не интересно', 'не надо', 'откажусь', 'не буду']
        if any(word in text_lower for word in negative_words):
            return Intent.NEGATIVE
        
        # Check for questions
        question_words = ['что', 'как', 'где', 'когда', 'почему', 'зачем', 'сколько']
        if any(text_lower.startswith(word) for word in question_words) or text_lower.endswith('?'):
            return Intent.QUESTION
        
        # Default
        return Intent.UNKNOWN
    
    def _handle_greeting(self, text: str, intent: Intent) -> str:
        """Handle GREETING state"""
        self._transition(DialogueState.INTRO, "greeting complete")
        return (
            "Здравствуйте! Меня зовут Алиса, я представляю компанию Новофон. "
            "У меня есть для вас интересное предложение. Удобно сейчас разговаривать?"
        )
    
    def _handle_intro(self, text: str, intent: Intent) -> str:
        """Handle INTRO state"""
        if intent == Intent.POSITIVE:
            self._transition(DialogueState.OFFER, "user available")
            return (
                "Отлично! Мы предлагаем современное решение для автоматизации звонков. "
                "Это поможет вам сэкономить время и увеличить продажи. "
                "Интересует подробная информация?"
            )
        
        elif intent == Intent.NEGATIVE:
            self._transition(DialogueState.OBJECTION_HANDLING, "user busy")
            return "Понимаю, что сейчас неудобно. Может быть, перезвоним в другое время?"
        
        else:
            return "Извините, не расслышала. Вам удобно сейчас разговаривать?"
    
    def _handle_offer(self, text: str, intent: Intent) -> str:
        """Handle OFFER state"""
        if intent == Intent.POSITIVE:
            self.context.offer_accepted = True
            self._transition(DialogueState.AGREEMENT, "offer accepted")
            return (
                "Замечательно! Наше решение включает автоматический обзвон клиентов, "
                "голосового робота для первичного контакта, и детальную аналитику. "
                "Стоимость от 5000 рублей в месяц. Подходит?"
            )
        
        elif intent == Intent.NEGATIVE:
            self.context.objections_count += 1
            self._transition(DialogueState.OBJECTION_HANDLING, "offer declined")
            return "Понимаю ваши сомнения. Могу ответить на вопросы. Что вас смущает?"
        
        elif intent == Intent.QUESTION:
            self._transition(DialogueState.CLARIFICATION, "need clarification")
            return "С удовольствием отвечу на ваши вопросы. Что именно вас интересует?"
        
        else:
            return "Вас интересует наше предложение?"
    
    def _handle_clarification(self, text: str, intent: Intent) -> str:
        """Handle CLARIFICATION state"""
        # In real implementation, would use NLU to understand question
        self._transition(DialogueState.OFFER, "clarification provided")
        return (
            "Наше решение работает следующим образом: голосовой робот звонит по вашей базе, "
            "проводит первичный диалог, квалифицирует клиента и передает горячие лиды вашим менеджерам. "
            "Это освобождает время вашей команды. Интересно?"
        )
    
    def _handle_objection(self, text: str, intent: Intent) -> str:
        """Handle OBJECTION_HANDLING state"""
        if self.context.objections_count >= 3:
            self._transition(DialogueState.FINAL, "too many objections")
            return (
                "Понимаю. Оставлю вам наши контакты, если передумаете - будем рады помочь. "
                "Спасибо за время. До свидания!"
            )
        
        if intent == Intent.POSITIVE:
            self._transition(DialogueState.OFFER, "objection resolved")
            return "Отлично! Тогда позвольте рассказать подробнее о нашем решении."
        
        elif intent == Intent.NEGATIVE:
            self.context.objections_count += 1
            return "Понимаю ваши опасения. Может быть, есть другие вопросы?"
        
        else:
            self._transition(DialogueState.OFFER, "back to offer")
            return "Хорошо, предлагаю вернуться к обсуждению. Интересует автоматизация звонков?"
    
    def _handle_agreement(self, text: str, intent: Intent) -> str:
        """Handle AGREEMENT state"""
        if intent == Intent.POSITIVE:
            self._transition(DialogueState.DETAILS, "collecting details")
            return (
                "Отлично! Чтобы подготовить персональное предложение, "
                "уточните, пожалуйста, какой у вас примерный объем звонков в месяц?"
            )
        
        elif intent == Intent.NEGATIVE:
            self._transition(DialogueState.OBJECTION_HANDLING, "price objection")
            return "Понимаю. Возможно, есть вопросы по функционалу или стоимости?"
        
        else:
            return "Наше предложение вас устраивает?"
    
    def _handle_details(self, text: str, intent: Intent) -> str:
        """Handle DETAILS state"""
        # Store details in context
        self.context.custom_data['volume_mentioned'] = text
        self._transition(DialogueState.CONFIRMATION, "details collected")
        return (
            "Спасибо за информацию! Мы подготовим для вас персональное предложение "
            "и вышлем на вашу почту. Могу я уточнить вашу электронную почту?"
        )
    
    def _handle_confirmation(self, text: str, intent: Intent) -> str:
        """Handle CONFIRMATION state"""
        if '@' in text:
            self.context.custom_data['email'] = text
        self._transition(DialogueState.FINAL, "confirmation complete")
        return (
            "Отлично, спасибо! В течение часа вы получите наше предложение. "
            "Наш менеджер свяжется с вами для уточнения деталей. "
            "Спасибо за уделенное время! До свидания!"
        )
    
    def _handle_final(self, text: str, intent: Intent) -> str:
        """Handle FINAL state"""
        self._transition(DialogueState.GOODBYE, "call ending")
        return "До свидания!"
    
    def _get_repeat_message(self) -> str:
        """Get repeat message for current state"""
        repeats = {
            DialogueState.GREETING: "Алло? Меня слышно?",
            DialogueState.INTRO: "Вы меня слышите? Вам удобно сейчас разговаривать?",
            DialogueState.OFFER: "Алло? Вас интересует наше предложение?",
            DialogueState.CLARIFICATION: "Есть вопросы по нашему предложению?",
            DialogueState.OBJECTION_HANDLING: "Вы меня слышите?",
            DialogueState.AGREEMENT: "Наше предложение вас устраивает?",
            DialogueState.DETAILS: "Можете назвать примерный объем звонков?",
            DialogueState.CONFIRMATION: "Можете назвать вашу электронную почту?",
        }
        return repeats.get(self.state, "Алло? Вы меня слышите?")
    
    def get_call_result(self) -> Dict[str, Any]:
        """
        Get call result summary
        
        Returns:
            Dictionary with call results
        """
        return {
            'final_state': self.state.value,
            'offer_accepted': self.context.offer_accepted,
            'objections_count': self.context.objections_count,
            'conversation_length': len(self.history),
            'context_data': self.context.custom_data
        }

