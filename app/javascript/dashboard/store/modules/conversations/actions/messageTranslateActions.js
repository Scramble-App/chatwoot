import MessageApi from '../../../../api/inbox/message';
import mutationTypes from '../../../mutation-types';

export default {
  async translateMessage(
    { commit },
    { conversationId, messageId, targetLanguage }
  ) {
    try {
      const { data } = await MessageApi.translateMessage(
        conversationId,
        messageId,
        targetLanguage
      );
      if (data?.operator_translation) {
        commit(mutationTypes.UPDATE_MESSAGE_TRANSLATION, {
          conversation_id: conversationId,
          message_id: messageId,
          operator_translation: data.operator_translation,
        });
      }
    } catch (error) {
      // ignore error
    }
  },
};
